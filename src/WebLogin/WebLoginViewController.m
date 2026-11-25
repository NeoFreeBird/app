#import "WebLoginViewController.h"
#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Hooks/WebCreateTweet/WebCreateTweet.h"

static NSString* const kWebLoginUserAgent =
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36";

// uid comes from the same site's native cookie snapshot.
static NSString* const kWebLoginScannerJS =
    @"const validHandle = value => typeof value === 'string' && /^[a-zA-Z0-9_]{1,15}$/.test(value);"
     "const state = window.__INITIAL_STATE__;"
     "const user = state?.entities?.users?.entities?.[uid];"
     "if (validHandle(user?.screen_name)) return user.screen_name;"
     "const visited = new Set();"
     "for (const element of [document.querySelector('main'), document.querySelector('article'), document]) {"
     "  if (!element) continue;"
     "  for (const key of Object.keys(element)) {"
     "    if (!/^__react(?:Fiber|Container)\\$/.test(key)) continue;"
     "    let fiber = element[key];"
     "    while (fiber?.return) fiber = fiber.return;"
     "    const root = fiber?.stateNode?.current;"
     "    if (!root) continue;"
     "    const pending = [root];"
     "    while (pending.length) {"
     "      const node = pending.pop();"
     "      if (visited.has(node)) continue;"
     "      visited.add(node);"
     "      for (const router of [node.memoizedProps?.router, node.memoizedProps?.value]) {"
     "        const context = router?.options?.context;"
     "        if (typeof router?.navigate !== 'function' || String(context?.viewerId) !== uid) continue;"
     "        if (validHandle(context.viewerScreenName)) return context.viewerScreenName;"
     "      }"
     "      if (node.sibling) pending.push(node.sibling);"
     "      if (node.child) pending.push(node.child);"
     "    }"
     "  }"
     "}"
     "if (!allowLegacyProfile) return null;"
     "const profile = document.querySelector('a[data-testid=\"AppTabBar_Profile_Link\"]');"
     "const handle = /^\\/([a-zA-Z0-9_]{1,15})\\/?$/.exec(profile?.getAttribute('href') ?? '')?.[1];"
     "return handle ?? null;";

static NSString* loginSiteForHost(NSString* host) {
    NSString* domain = host.lowercaseString;
    if ([domain isEqualToString:@"x.com"] || [domain hasSuffix:@".x.com"]) {
        return @"x.com";
    }
    if ([domain isEqualToString:@"twitter.com"] || [domain hasSuffix:@".twitter.com"]) {
        return @"twitter.com";
    }
    return nil;
}

static NSDictionary<NSString*, NSString*>* loginCookiesForSite(
    NSArray<NSHTTPCookie*>* cookies, NSString* site) {
    NSMutableDictionary<NSString*, NSString*>* values = [NSMutableDictionary dictionary];
    NSString* domainCookieHost = [@"." stringByAppendingString:site];
    for (NSHTTPCookie* cookie in cookies) {
        NSString* domain = cookie.domain.lowercaseString;
        if ((![domain isEqualToString:site] && ![domain isEqualToString:domainCookieHost]) ||
            ![cookie.path isEqualToString:@"/"] || !cookie.value.length) {
            continue;
        }
        // Prefer the site-wide cookie when both it and a host-only cookie are present.
        if (!values[cookie.name] || [domain isEqualToString:domainCookieHost]) {
            values[cookie.name] = cookie.value;
        }
    }
    return values;
}

static NSString* userIDFromTwid(NSString* twid) {
    NSString* decoded = [twid stringByRemovingPercentEncoding] ?: twid;
    if (decoded.length >= 2 && [decoded hasPrefix:@"\""] && [decoded hasSuffix:@"\""]) {
        decoded = [decoded substringWithRange:NSMakeRange(1, decoded.length - 2)];
    }
    if (![decoded hasPrefix:@"u="] || decoded.length <= 2) {
        return nil;
    }
    NSString* userID = [decoded substringFromIndex:2];
    NSCharacterSet* digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    return [userID rangeOfCharacterFromSet:digits.invertedSet].location == NSNotFound ? userID : nil;
}

static id performShared(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static NSString* stringOrEmpty(NSString* value) { return value ?: @""; }

static BOOL getAccountUserID(id account, long long* userID) {
    if (!account || !userID || ![account respondsToSelector:@selector(userID)]) {
        return NO;
    }

    Method method = class_getInstanceMethod([account class], @selector(userID));
    const char* returnType = method ? method_copyReturnType(method) : NULL;
    BOOL isObject = returnType && returnType[0] == '@';
    long long value = 0;
    if (isObject) {
        id objectValue = ((id (*)(id, SEL))objc_msgSend)(account, @selector(userID));
        if ([objectValue respondsToSelector:@selector(longLongValue)]) {
            value = [objectValue longLongValue];
        } else {
            if (returnType) free((void*)returnType);
            return NO;
        }
    } else if (returnType && (returnType[0] == 'q' || returnType[0] == 'Q' ||
                              returnType[0] == 'l' || returnType[0] == 'L')) {
        value = ((long long (*)(id, SEL))objc_msgSend)(account, @selector(userID));
    } else {
        if (returnType) free((void*)returnType);
        return NO;
    }
    if (returnType) free((void*)returnType);
    *userID = value;
    return YES;
}

// Objects are cleaner and don't crash like using raw selectors
@protocol WebLoginObjectUserIDAccount <NSObject>
- (instancetype)initWithUsername:(NSString*)username userID:(id)userID;
@end

@protocol WebLoginIntegerUserIDAccount <NSObject>
- (instancetype)initWithUsername:(NSString*)username userID:(long long)userID;
@end

static id accountWithUsernameAndUserID(Class accountClass, NSString* username,
                                       long long userID) {
    SEL selector = @selector(initWithUsername:userID:);
    Method method = class_getInstanceMethod(accountClass, selector);
    if (!method) {
        return nil;
    }

    const char* argumentType = method_copyArgumentType(method, 3);
    id account = nil;
    if (argumentType && argumentType[0] == '@') {
        account = [(id<WebLoginObjectUserIDAccount>)[accountClass alloc]
            initWithUsername:username
                      userID:@(userID)];
    } else if (argumentType && (argumentType[0] == 'q' || argumentType[0] == 'Q' ||
                                argumentType[0] == 'l' || argumentType[0] == 'L')) {
        account = [(id<WebLoginIntegerUserIDAccount>)[accountClass alloc]
            initWithUsername:username
                      userID:userID];
    }
    if (argumentType) free((void*)argumentType);
    return account;
}

@interface WebLoginViewController () <WKNavigationDelegate, WKHTTPCookieStoreObserver>
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) NSTimer* pollTimer;
@property (nonatomic, strong) WKHTTPCookieStore* observedCookieStore;
@property (nonatomic, assign) BOOL asRootScreen;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL sessionCheckInFlight;
@property (nonatomic, assign) BOOL reportedHandoffFailure;
@end

@implementation WebLoginViewController

#pragma mark - Presentation

+ (BOOL)bht_isOurs:(UIViewController*)vc {
    if ([vc isKindOfClass:[WebLoginViewController class]]) {
        return YES;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        id root = ((UINavigationController*)vc).viewControllers.firstObject;
        return [root isKindOfClass:[WebLoginViewController class]];
    }
    return NO;
}

+ (void)presentLoginFrom:(UIViewController*)presenter {
    if (!presenter) {
        return;
    }
    for (UIViewController* vc = presenter; vc; vc = vc.presentedViewController) {
        if ([self bht_isOurs:vc]) {
            return;
        }
    }
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }

    WebLoginViewController* login = [[WebLoginViewController alloc] init];
    UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:login];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:nav animated:YES completion:nil];
}

+ (UINavigationController*)loginRootNavigationController {
    WebLoginViewController* login = [[WebLoginViewController alloc] init];
    login.asRootScreen = YES;
    return [[UINavigationController alloc] initWithRootViewController:login];
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = [[BHTBundle sharedBundle] localizedStringForKey:@"LOG_IN_TITLE"];

    if (!self.asRootScreen) {
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                          target:self
                                                          action:@selector(cancelTapped)];
    }

    WKWebViewConfiguration* cfg = [[WKWebViewConfiguration alloc] init];
    // Make sure the webview is always logged out, otherwise it'll duplicate the existing session
    cfg.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:cfg];
    self.webView.navigationDelegate = self;
    self.webView.customUserAgent = kWebLoginUserAgent;
    if (@available(iOS 16.4, *)) {
        self.webView.inspectable = YES;
    }
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.webView];

    NSURL* url = [NSURL URLWithString:@"https://x.com/login"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.finished || self.pollTimer) return;
    __weak typeof(self) weakSelf = self;
    self.observedCookieStore = self.webView.configuration.websiteDataStore.httpCookieStore;
    [self.observedCookieStore addObserver:self];
    self.pollTimer = [NSTimer timerWithTimeInterval:1.5
                                            repeats:YES
                                              block:^(__unused NSTimer* timer) {
                                                  [weakSelf checkForSession];
                                              }];
    [[NSRunLoop mainRunLoop] addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
    [self checkForSession];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopSessionMonitoring];
}

- (void)dealloc {
    [_observedCookieStore removeObserver:self];
    [_pollTimer invalidate];
}

- (void)stopSessionMonitoring {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    [self.observedCookieStore removeObserver:self];
    self.observedCookieStore = nil;
}

- (void)cancelTapped {
    self.finished = YES;
    [self stopSessionMonitoring];
    [self.webView stopLoading];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Navigation delegate

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
    [self checkForSession];
}

#pragma mark - Session capture

- (void)cookiesDidChangeInCookieStore:(WKHTTPCookieStore*)cookieStore {
    if (cookieStore == self.observedCookieStore) {
        [self checkForSession];
    }
}

- (void)checkForSession {
    if (self.finished || self.sessionCheckInFlight || !self.observedCookieStore || !self.view.window) {
        return;
    }
    self.sessionCheckInFlight = YES;

    [self.observedCookieStore getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
        if (self.finished || !self.observedCookieStore || !self.view.window) {
            self.sessionCheckInFlight = NO;
            return;
        }

        WKWebView* webView = self.webView;
        NSString* pageSite = loginSiteForHost(webView.URL.host);
        if (!pageSite) {
            self.sessionCheckInFlight = NO;
            return;
        }
        NSString* otherSite = [pageSite isEqualToString:@"x.com"] ? @"twitter.com" : @"x.com";
        for (NSString* site in @[pageSite, otherSite]) {
            NSDictionary<NSString*, NSString*>* values = loginCookiesForSite(cookies, site);
            NSString* authToken = values[@"auth_token"];
            NSString* ct0 = values[@"ct0"];
            NSString* twid = values[@"twid"];
            NSString* userID = userIDFromTwid(twid);
            // Cookies can arrive separately. Read the complete session from the same site's snapshot.
            if (!authToken.length || !ct0.length || !userID.length) {
                continue;
            }

            [webView callAsyncJavaScript:kWebLoginScannerJS
                arguments:@{
                    @"uid": userID,
                    @"allowLegacyProfile": @([site isEqualToString:pageSite]),
                }
                inFrame:nil
                inContentWorld:WKContentWorld.pageWorld
                completionHandler:^(id result, __unused NSError* error) {
                    self.sessionCheckInFlight = NO;
                    if (self.finished || !self.observedCookieStore || !self.view.window ||
                        ![loginSiteForHost(webView.URL.host) isEqualToString:pageSite]) {
                        return;
                    }
                    NSString* username = [result isKindOfClass:[NSString class]] ? result : nil;
                    id existing = [self existingAccountForUserID:userID.longLongValue];
                    if (!username.length && (!existing || ![site isEqualToString:pageSite])) {
                        // A new native account needs the real handle. Recheck after hydration.
                        return;
                    }

                    [self syncCookies:cookies forSite:site];
                    [self finishWithUserID:userID
                                  username:username
                                 authToken:authToken
                                       ct0:ct0
                                      twid:twid
                                 authMulti:values[@"auth_multi"]
                           existingAccount:existing];
                }];
            return;
        }
        self.sessionCheckInFlight = NO;
    }];
}

// Share the selected site's cookies with the app's NSURLSession stack.
- (void)syncCookies:(NSArray<NSHTTPCookie*>*)cookies forSite:(NSString*)site {
    NSHTTPCookieStorage* storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie* cookie in cookies) {
        if ([loginSiteForHost(cookie.domain) isEqualToString:site]) {
            [storage setCookie:cookie];
        }
    }
}

- (void)finishWithUserID:(NSString*)userID
                username:(NSString*)username
               authToken:(NSString*)authToken
                     ct0:(NSString*)ct0
                    twid:(NSString*)twid
               authMulti:(NSString*)authMulti
         existingAccount:(id)existingAccount {
    if (self.finished) {
        return;
    }
    NSMutableDictionary<NSString*, NSString*>* pairs = [NSMutableDictionary dictionary];
    pairs[@"auth_token"] = authToken;
    pairs[@"ct0"] = ct0;
    pairs[@"twid"] = twid;
    if (authMulti.length) {
        pairs[@"auth_multi"] = authMulti;
    }

    // Hand the session to WebCreateTweet.x
    webLoginDidCaptureCookies(userID, username, pairs);

    id account = existingAccount ?: [self registerNativeAccountForUserID:userID
                                                                username:username
                                                               authToken:authToken];
    if (!account) {
        if (!self.reportedHandoffFailure) {
            self.reportedHandoffFailure = YES;
        }
        return;
    }

    self.finished = YES;
    [self stopSessionMonitoring];
    if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     [self switchToAccount:account];
                                 }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self switchToAccount:account];
        });
    }
}

#pragma mark - Native account registration

// Register a dummy OAuth1 account in the native store so any code that reads the account's oauth token still recovers the correct userID.
- (id)registerNativeAccountForUserID:(NSString*)userID
                            username:(NSString*)username
                           authToken:(NSString*)authToken {
    Class accountCls = objc_getClass("TFNTwitterAccount");
    if (!accountCls) {
        return nil;
    }

    long long uid = userID.longLongValue;

    id account = accountWithUsernameAndUserID(accountCls, username, uid);
    if (!account) {
        return nil;
    }

    // Stamp a placeholder credential in the native "<userID>-<token>" shape so any code
    // that parses the account's oauth token still recovers the correct userID.
    if ([account respondsToSelector:@selector(updateUserInfoAndCredentialsWithToken:secret:username:)]) {
        NSString* placeholderToken = [NSString stringWithFormat:@"%@-%@", userID, authToken ?: @""];
        @try {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(
                account, @selector(updateUserInfoAndCredentialsWithToken:secret:username:),
                placeholderToken, stringOrEmpty(authToken), username ?: @"");
        } @catch (__unused NSException* exception) {
        }
    }

    return [self addAccountToStore:account userID:uid];
}

- (id)existingAccountForUserID:(long long)uid {
    if (uid == 0) {
        return nil;
    }
    @try {
        id shared = performShared(objc_getClass("TFNTwitter"), @selector(sharedTwitter));
        id accounts = performShared(shared, @selector(accounts));
        if ([accounts isKindOfClass:[NSArray class]]) {
            for (id acct in accounts) {
                long long accountUserID = 0;
                if (getAccountUserID(acct, &accountUserID) && accountUserID == uid) {
                    return acct;
                }
            }
        }
    } @catch (__unused NSException* exception) {
    }
    return nil;
}

- (id)addAccountToStore:(id)account userID:(long long)userID {
    @try {
        Class twitterCls = objc_getClass("TFNTwitter");
        id shared = performShared(twitterCls, @selector(sharedTwitter));
        id service = performShared(shared, @selector(accountService));
        if (![service respondsToSelector:@selector(addAccount:)]) {
            return nil;
        }
        ((void (*)(id, SEL, id))objc_msgSend)(service, @selector(addAccount:), account);
        if ([twitterCls respondsToSelector:@selector(saveSharedTwitter)]) {
            ((void (*)(id, SEL))objc_msgSend)(twitterCls, @selector(saveSharedTwitter));
        }

        id storedAccount = [self existingAccountForUserID:userID];
        if (storedAccount) {
            Class notifCls = objc_getClass("TFSAccountNotification");
            id name = performShared(notifCls, @selector(TFSAccountsDidChange));
            if ([name isKindOfClass:[NSString class]]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:name
                                                                    object:shared
                                                                  userInfo:nil];
            }
        }
        return storedAccount;
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

- (void)switchToAccount:(id)account {
    if (!account) {
        return;
    }
    id host = performShared(objc_getClass("T1HostViewController"), @selector(sharedHostViewController));
    if (host && [host respondsToSelector:@selector(viewAccount:animated:)]) {
        @try {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(host, @selector(viewAccount:animated:),
                                                        account, YES);
        } @catch (__unused NSException* exception) {
        }
    }
}

@end
