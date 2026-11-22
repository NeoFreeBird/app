#import "WebCreateTweetInternal.h"

static WKWebView* WebHelperWebView = nil;
static BOOL WebHelperReady = NO;
static BOOL WebHelperInFlight = NO;

static NSMutableDictionary<NSString*, NSString*>* WebXTIDByPath = nil;
static NSMutableSet<NSString*>* WebXTIDInFlightKeys = nil;
// Requests blocked in BHTTransactionIDForRequest (key -> @[method, path]), served as soon as the helper is ready.
static NSMutableDictionary<NSString*, NSArray<NSString*>*>* WebXTIDWaiters = nil;
// While the helper can't produce ids (page changed, session rejected, ...), requests don't wait for one
// until this time, so a broken helper costs one bounded wait per cooldown, not one per request.
static CFAbsoluteTime WebXTIDGiveUpUntil = 0;
static NSObject* WebXTIDLock = nil;

static UIWindow* WebHarvestWindow = nil;
static BOOL WebBootstrapInFlight = NO;

static const void* WebHarvestWebViewKey = &WebHarvestWebViewKey;

static void refreshXTIDForMethodPath(NSString* method, NSString* path);
static void prewarmCreateTweetXTID(void);
static void serveXTIDWaiters(void);
static NSString* cachedXTIDForKey(NSString* key);
static NSString* xtidKey(NSString* method, NSString* path);
static void teardownWebHarvestWindow(void);

static UIWindowScene* activeWindowScene(void) {
    UIWindowScene* fallback = nil;
    for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene*)scene;
        }
        if (!fallback) {
            fallback = (UIWindowScene*)scene;
        }
    }
    return fallback;
}

// Runs `ready` in a tight poll off the main thread, kicking `kick` every ~3s, until it
// passes or the deadline elapses. Never blocks the main thread.
static BOOL waitUntil(BOOL (^ready)(void), void (^kick)(void), NSTimeInterval maxSeconds) {
    if (ready()) {
        return YES;
    }
    if ([NSThread isMainThread]) {
        return NO;
    }

    NSUInteger maxTicks = (NSUInteger)(maxSeconds / 0.05);
    for (NSUInteger tick = 0; tick < maxTicks && !ready(); tick++) {
        if (kick && (tick % 60 == 0)) {
            dispatch_async(dispatch_get_main_queue(), kick);
        }
        [NSThread sleepForTimeInterval:0.05];
    }
    return ready();
}

// MARK: - Helper webview (x-client-transaction-id)

static void onHelperWebViewLoaded(WKWebView* webView);

@interface WebHelperDelegate : NSObject <WKNavigationDelegate>
@end
@implementation WebHelperDelegate
- (void)webView:(WKWebView*)webView didFinishNavigation:(__unused WKNavigation*)navigation {
    onHelperWebViewLoaded(webView);
}
- (void)webView:(WKWebView*)webView
    didFailProvisionalNavigation:(__unused WKNavigation*)navigation
                       withError:(__unused NSError*)error {
    if (webView != WebHelperWebView) return;
    [webView stopLoading];
    [webView removeFromSuperview];
    webView.navigationDelegate = nil;
    WebHelperWebView = nil;
    WebHelperReady = NO;
    WebHelperInFlight = NO;
}
@end

static WebHelperDelegate* WebHelperDelegateInstance = nil;

// Seed the helper webview's cookie store with the harvested session cookies so it loads authenticated.
static void seedHelperCookies(WKWebView* webView, void (^done)(void)) {
    NSDictionary* pairs = BHTCurrentWebSessionCookies();
    BHTSeedWebSessionCookies(webView.configuration.websiteDataStore.httpCookieStore, pairs, done);
}

void BHTSeedWebSessionCookies(WKHTTPCookieStore* store, NSDictionary<NSString*, NSString*>* pairs,
                              void (^done)(void)) {
    done = done ?: ^{
    };

    NSMutableArray<NSHTTPCookie*>* cookies = [NSMutableArray array];
    for (NSString* domain in @[@".x.com", @".twitter.com"]) {
        for (NSString* name in pairs) {
            NSString* value = pairs[name];
            if (value.length == 0) {
                continue;
            }
            NSHTTPCookie* cookie = [NSHTTPCookie cookieWithProperties:@{
                NSHTTPCookieName: name,
                NSHTTPCookieValue: value,
                NSHTTPCookieDomain: domain,
                NSHTTPCookiePath: @"/",
                NSHTTPCookieSecure: @"TRUE",
            }];
            if (cookie) {
                [cookies addObject:cookie];
            }
        }
    }

    if (!store || cookies.count == 0) {
        done();
        return;
    }

    __block NSUInteger remaining = cookies.count;
    for (NSHTTPCookie* cookie in cookies) {
        [store setCookie:cookie
            completionHandler:^{
                if (--remaining == 0) {
                    done();
                }
            }];
    }
}

void BHTRefreshWebCookiesViaWebView(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ BHTRefreshWebCookiesViaWebView(); });
        return;
    }
    if (WebHelperWebView) {
        if (WebHelperReady &&
            (!cachedXTIDForKey(xtidKey(@"POST", BHTCreateTweetPath())).length ||
             !cachedXTIDForKey(xtidKey(@"POST", BHTCreateNoteTweetPath())).length)) {
            prewarmCreateTweetXTID();
        }
        return;
    }
    if (WebHelperInFlight) {
        return;
    }
    WebHelperInFlight = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        BHTHarvestSharedCookies();

        WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;

        WKWebView* webView = [[WKWebView alloc] initWithFrame:CGRectMake(-3000, -3000, 390, 844)
                                                configuration:configuration];
        WebHelperDelegateInstance = [[WebHelperDelegate alloc] init];
        webView.navigationDelegate = WebHelperDelegateInstance;
        webView.customUserAgent = BHTWebSessionUserAgent;
        webView.userInteractionEnabled = NO;
        webView.alpha = 0.01;
        WebHelperWebView = webView;
        WebHelperReady = NO;

        UIWindow* keyWindow = nil;
        for (UIWindow* w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) {
                keyWindow = w;
                break;
            }
        }
        keyWindow = keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
        [keyWindow addSubview:webView];

        seedHelperCookies(webView, ^{
            [webView
                loadRequest:[NSURLRequest
                                requestWithURL:[NSURL URLWithString:@"https://x.com/settings/account"]]];
        });
    });
}

static void onHelperWebViewLoaded(WKWebView* webView) {
    if (webView != WebHelperWebView) return;
    WebHelperInFlight = NO;

    [webView.configuration.websiteDataStore.httpCookieStore
        getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
            BHTStoreWebCookies(cookies);
        }];

    NSString* script = nil;
    NSURL* scriptURL = [[BHTBundle sharedBundle] pathForFile:@"WebXTID.js"];
    if (scriptURL) {
        script = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
    }
    if (script.length == 0) {
        return;
    }

    [webView evaluateJavaScript:script
              completionHandler:^(__unused id result, __unused NSError* error) {
                  if (error || webView != WebHelperWebView) return;
                  WebHelperReady = YES;
                  prewarmCreateTweetXTID();
                  serveXTIDWaiters();
              }];
}

static NSObject* xtidLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WebXTIDLock = [NSObject new];
        WebXTIDByPath = [NSMutableDictionary dictionary];
        WebXTIDInFlightKeys = [NSMutableSet set];
        WebXTIDWaiters = [NSMutableDictionary dictionary];
    });
    return WebXTIDLock;
}

static NSString* xtidKey(NSString* method, NSString* path) {
    return [NSString stringWithFormat:@"%@ %@", method ?: @"POST", path ?: @""];
}

static NSString* cachedXTIDForKey(NSString* key) {
    @synchronized(xtidLock()) {
        return WebXTIDByPath[key];
    }
}

// Mint (or rotate) the transaction id for one (method, path) by calling the web
// client's own generator in the helper webview. Deduped per key so concurrent sends
// for the same path issue a single JS call.
static void refreshXTIDForMethodPath(NSString* method, NSString* path) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ refreshXTIDForMethodPath(method, path); });
        return;
    }
    if (!WebHelperReady) return;
    if (path.length == 0) {
        return;
    }
    NSString* key = xtidKey(method, path);
    @synchronized(xtidLock()) {
        if ([WebXTIDInFlightKeys containsObject:key]) {
            return;
        }
        [WebXTIDInFlightKeys addObject:key];
    }

    WKWebView* webView = WebHelperWebView;
    if (![webView isKindOfClass:[WKWebView class]]) {
        @synchronized(xtidLock()) {
            [WebXTIDInFlightKeys removeObject:key];
        }
        return;
    }

    if (@available(iOS 14.0, *)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [webView callAsyncJavaScript:@"return await window.__bhtTransactionId(path, method);"
                               arguments:@{@"method": method ?: @"POST", @"path": path}
                                 inFrame:nil
                          inContentWorld:WKContentWorld.pageWorld
                       completionHandler:^(id result, __unused NSError* error) {
                           BOOL ok = [result isKindOfClass:[NSString class]] &&
                                     [(NSString*)result length] > 10 &&
                                     ![(NSString*)result hasPrefix:@"ERR:"];
                           @synchronized(xtidLock()) {
                               [WebXTIDInFlightKeys removeObject:key];
                               if (ok) {
                                   WebXTIDByPath[key] = [result copy];
                                   WebXTIDGiveUpUntil = 0;
                               }
                           }
                       }];
        });
    } else {
        @synchronized(xtidLock()) {
            [WebXTIDInFlightKeys removeObject:key];
        }
    }
}

static void prewarmCreateTweetXTID(void) {
    refreshXTIDForMethodPath(@"POST", BHTCreateTweetPath());
    refreshXTIDForMethodPath(@"POST", BHTCreateNoteTweetPath());
}

// Generation is local to the helper page (no network), and refreshXTIDForMethodPath dedupes per key.
static void serveXTIDWaiters(void) {
    NSArray<NSArray<NSString*>*>* waiters;
    @synchronized(xtidLock()) {
        waiters = WebXTIDWaiters.allValues;
    }
    for (NSArray<NSString*>* waiter in waiters) {
        refreshXTIDForMethodPath(waiter[0], waiter[1]);
    }
}

// The wait runs on the app's shared network queue, so it is kept short: a healthy helper answers in
// about a second. Sending without an id is what already happens when the wait times out.
static const NSTimeInterval XTIDMaxWait = 6.0;
static const NSTimeInterval XTIDGiveUpCooldown = 30.0;

static BOOL isPostMutationPath(NSString* path) {
    return [path hasSuffix:@"/CreateTweet"] || [path hasSuffix:@"/CreateNoteTweet"];
}

// Asks whichever stage the helper is in to make progress: create it, or mint this id.
static void kickXTIDGeneration(NSString* method, NSString* path) {
    if (!WebHelperWebView) {
        BHTRefreshWebCookiesViaWebView();
    } else if (WebHelperReady) {
        refreshXTIDForMethodPath(method, path);
    }
}

NSString* BHTTransactionIDForRequest(NSURLRequest* request) {
    NSURL* url = request.URL;
    if (url.path.length == 0) {
        return nil;
    }
    NSString* method = (request.HTTPMethod ?: @"POST").uppercaseString;

    NSString* key = xtidKey(method, url.path);
    NSString* cached = cachedXTIDForKey(key);
    if (cached.length) {
        refreshXTIDForMethodPath(method, url.path);
        return cached;
    }

    // Posts always wait (the user is waiting on them, and they have a native fallback); everything else
    // skips the wait while the helper is known to be failing, and just retries in the background.
    BOOL isPost = isPostMutationPath(url.path);
    BOOL coolingDown;
    @synchronized(xtidLock()) {
        coolingDown = CFAbsoluteTimeGetCurrent() < WebXTIDGiveUpUntil;
        if (!coolingDown || isPost) {
            WebXTIDWaiters[key] = @[method, url.path];
        }
    }
    if (coolingDown && !isPost) {
        dispatch_async(dispatch_get_main_queue(), ^{ kickXTIDGeneration(method, url.path); });
        return nil;
    }

    BOOL got = waitUntil(
        ^BOOL {
            return cachedXTIDForKey(key).length > 0;
        },
        ^{ kickXTIDGeneration(method, url.path); }, XTIDMaxWait);
    @synchronized(xtidLock()) {
        [WebXTIDWaiters removeObjectForKey:key];
        if (!got && ![NSThread isMainThread]) {
            WebXTIDGiveUpUntil = CFAbsoluteTimeGetCurrent() + XTIDGiveUpCooldown;
        }
    }
    return cachedXTIDForKey(key);
}

// MARK: - Native bootstrap webview (per-account web session)

// Only the native authenticated webview can perform the OAuth->cookie exchange, so
// accounts with no web cookies yet get one loaded offscreen and harvested.
static void bootstrapAccount(id account, NSString* userID) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ bootstrapAccount(account, userID); });
        return;
    }
    if (!account || userID.length == 0 || WebBootstrapInFlight) {
        return;
    }
    WebBootstrapInFlight = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (WebHarvestWindow) {
            WebHarvestWindow.hidden = YES;
            WebHarvestWindow.rootViewController = nil;
            WebHarvestWindow = nil;
        }

        Class webViewControllerClass = NSClassFromString(@"T1WebViewController");
        SEL initSel = @selector(initWithRootURL:
                                account:shouldAuthenticate:shouldPresentAsNativePage:
                                sourceStatus:scribeComponent:scribeParameters:);
        UIWindowScene* scene = activeWindowScene();
        if (!webViewControllerClass || !scene ||
            ![webViewControllerClass instancesRespondToSelector:initSel]) {
            WebBootstrapInFlight = NO;
            return;
        }

        NSURL* url = [NSURL URLWithString:@"https://x.com/settings/account"];
        T1WebViewController* webViewController = [[webViewControllerClass alloc] initWithRootURL:url
                                                                                         account:account
                                                                              shouldAuthenticate:YES
                                                                       shouldPresentAsNativePage:NO
                                                                                    sourceStatus:nil
                                                                                 scribeComponent:nil
                                                                                scribeParameters:nil];
        if (!webViewController) {
            WebBootstrapInFlight = NO;
            return;
        }

        objc_setAssociatedObject(webViewController, WebHarvestWebViewKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIWindow* window = [[UIWindow alloc] initWithWindowScene:scene];
        window.frame = CGRectMake(-3000, -3000, 390, 844);
        window.windowLevel = UIWindowLevelNormal - 1000;
        window.userInteractionEnabled = NO;
        window.rootViewController = webViewController;
        window.hidden = NO;
        WebHarvestWindow = window;

        // Safety teardown in case the load never resolves.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           teardownWebHarvestWindow();
                       });
    });
}

static void teardownWebHarvestWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (WebHarvestWindow) {
            WebHarvestWindow.hidden = YES;
            WebHarvestWindow.rootViewController = nil;
            WebHarvestWindow = nil;
        }
        WebBootstrapInFlight = NO;
    });
}

void maybeHandleHarvestWebView(__unsafe_unretained id webViewController) {
    if (!webViewController || !objc_getAssociatedObject(webViewController, WebHarvestWebViewKey)) {
        return;
    }

    WKWebView* webView = nil;
    @try {
        if ([webViewController respondsToSelector:@selector(webView)]) {
            webView = ((WKWebView * (*)(id, SEL)) objc_msgSend)(webViewController, @selector(webView));
        }
    } @catch (__unused NSException* exception) {
    }

    void (^finish)(void) = ^{
        BHTHarvestSharedCookies();
        BHTRefreshWebCookiesViaWebView();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           teardownWebHarvestWindow();
                       });
    };

    if ([webView isKindOfClass:NSClassFromString(@"WKWebView")]) {
        [webView.configuration.websiteDataStore.httpCookieStore
            getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
                BHTStoreWebCookies(cookies);
                finish();
            }];
    } else {
        finish();
    }
}

static const void* WebViewSessionCookiesKey = &WebViewSessionCookiesKey;
static const void* WebStorePendingLoadKey = &WebStorePendingLoadKey;
// Marks a data store we seeded for a cookie-login session, so the loadRequest: hook can
// tell our authenticated webviews apart and bypass the native OAuth auth bridge.
static const void* WebStoreCookieLoginKey = &WebStoreCookieLoginKey;

void BHTSeedCookieLoginConfiguration(id webViewController, id configuration, id result) {
    id account = [webViewController respondsToSelector:@selector(account)]
                     ? [webViewController account]
                     : nil;
    NSDictionary* session = objc_getAssociatedObject(webViewController, WebViewSessionCookiesKey);
    if (!session) {
        session = BHTCachedWebSessionForAccount(account);
    }

    WKWebViewConfiguration* config =
        [result isKindOfClass:[WKWebViewConfiguration class]] ? result : configuration;
    if (!session || ![config isKindOfClass:[WKWebViewConfiguration class]]) {
        return;
    }
    if (objc_getAssociatedObject(config.websiteDataStore, WebStoreCookieLoginKey)) {
        return;
    }

    WKWebsiteDataStore* store = [WKWebsiteDataStore nonPersistentDataStore];
    config.websiteDataStore = store;

    objc_setAssociatedObject(store, WebStoreCookieLoginKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(store, WebStorePendingLoadKey, [NSMutableArray array],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BHTSeedWebSessionCookies(store.httpCookieStore, session, ^{
        NSArray* pending = objc_getAssociatedObject(store, WebStorePendingLoadKey);
        objc_setAssociatedObject(store, WebStorePendingLoadKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        void (^load)(void) = pending.lastObject;
        if (load) {
            load();
        }
    });
}

static NSURLRequest* unwrapAuthBridgeRequest(NSURLRequest* request) {
    NSURL* url = request.URL;
    if (![url.path containsString:@"/account/authenticate_web_view"]) {
        return request;
    }
    NSURLComponents* comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem* item in comps.queryItems) {
        if ([item.name isEqualToString:@"redirect_url"] && item.value.length) {
            NSURL* target = [NSURL URLWithString:item.value];
            if (target) {
                NSMutableURLRequest* out = [request mutableCopy];
                out.URL = target;
                return out;
            }
            break;
        }
    }
    return request;
}

void BHTRememberWebViewSession(id controller, NSDictionary* session) {
    if (session) {
        objc_setAssociatedObject(controller, WebViewSessionCookiesKey, session,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

void BHTCaptureWebViewSession(id controller, id account) {
    if (!objc_getAssociatedObject(controller, WebViewSessionCookiesKey)) {
        BHTRememberWebViewSession(controller, BHTCachedWebSessionForAccount(account));
    }
}

// nil means the latest request was queued until the cookies finish seeding.
NSURLRequest* BHTPrepareCookieLoginLoad(WKWebView* webView, NSURLRequest* request) {
    WKWebsiteDataStore* store = webView.configuration.websiteDataStore;
    NSURLRequest* effective = objc_getAssociatedObject(store, WebStoreCookieLoginKey)
                                  ? unwrapAuthBridgeRequest(request)
                                  : request;
    NSMutableArray* pending = objc_getAssociatedObject(store, WebStorePendingLoadKey);
    if (!pending) {
        return effective;
    }

    __weak WKWebView* weakWebView = webView;
    [pending removeAllObjects];
    [pending addObject:[^{ [weakWebView loadRequest:effective]; } copy]];
    return nil;
}
