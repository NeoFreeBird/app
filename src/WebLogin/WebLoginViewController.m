//
//  WebLoginViewController.m
//  NeoFreeBird
//

#import "WebLoginViewController.h"
#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/BHTBundle.h"

// Implemented in WebCreateTweet.x: seed the web-session cache for `userID` and mark it
// a cookie-login account so its native calls get re-signed with these cookies.
extern void webLoginDidCaptureCookies(NSString* userID, NSString* username,
                                      NSDictionary<NSString*, NSString*>* cookiePairs);

static NSString* const kWebLoginUserAgent =
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36";

// Pulls the numeric account id out of the twid cookie ("u=<id>", percent-encoded) and
// the screen name out of the loaded page. Posts one of:
//   "username:<handle>"        -> success, both id and handle resolved
//   "userid:<id>"              -> id resolved, handle not found yet (keep polling)
//   ""                         -> no session yet
static NSString* const kWebLoginScannerJS =
    @"(function(){"
     "var uid='';"
     "var m=document.cookie.match(/twid=u(?:%3D|=)(\\d+)/);"
     "if(m&&m[1]){uid=m[1];}"
     "if(!uid){return '';}"
     "function findHandle(text){"
     "if(!text)return null;"
     "var idx=text.indexOf(uid);"
     "if(idx===-1)return null;"
     "var sub=text.substring(Math.max(0,idx-1200),Math.min(text.length,idx+1200));"
     "var pats=[/\"screen_name\"\\s*:\\s*\"([a-zA-Z0-9_]{1,15})\"/g,"
     "/\"screenName\"\\s*:\\s*\"([a-zA-Z0-9_]{1,15})\"/g];"
     "for(var p=0;p<pats.length;p++){var mm;pats[p].lastIndex=0;"
     "while((mm=pats[p].exec(sub))!==null){var u=mm[1];"
     "if(!/^(home|explore|notifications|messages|settings|search|i|compose|login|signup|intent)$/i."
     "test(u))return u;}}"
     "return null;"
     "}"
     "try{if(window.__INITIAL_STATE__){var u=findHandle(JSON.stringify(window.__INITIAL_STATE__));"
     "if(u)return 'username:'+u;}}catch(e){}"
     "try{var s=document.getElementsByTagName('script');"
     "for(var i=0;i<s.length;i++){var u=findHandle(s[i].textContent||'');"
     "if(u)return 'username:'+u;}}catch(e){}"
     "return 'userid:'+uid;"
     "})();";

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

@interface WebLoginViewController () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) NSTimer* pollTimer;
@property (nonatomic, assign) BOOL asRootScreen;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL sessionCheckInFlight;
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
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                     repeats:YES
                                                       block:^(__unused NSTimer* timer) {
                                                           [weakSelf checkForSession];
                                                       }];
    [self checkForSession];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.pollTimer invalidate];
    self.pollTimer = nil;
}

- (void)dealloc {
    [_pollTimer invalidate];
}

- (void)cancelTapped {
    self.finished = YES;
    [self.webView stopLoading];
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Navigation delegate

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
    [self checkForSession];
}

#pragma mark - Session capture

- (void)checkForSession {
    if (self.finished || self.sessionCheckInFlight || !self.view.window) {
        return;
    }
    self.sessionCheckInFlight = YES;

    WKWebView* webView = self.webView;
    [webView.configuration.websiteDataStore.httpCookieStore
        getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
            if (self.finished || !self.view.window) {
                self.sessionCheckInFlight = NO;
                return;
            }
            NSString *authToken = nil, *ct0 = nil, *twid = nil, *authMulti = nil;
            for (NSHTTPCookie* cookie in cookies) {
                NSString* domain = cookie.domain ?: @"";
                if (![domain containsString:@"x.com"] && ![domain containsString:@"twitter.com"]) {
                    continue;
                }
                if (cookie.value.length == 0) {
                    continue;
                }
                if ([cookie.name isEqualToString:@"auth_token"]) {
                    authToken = cookie.value;
                } else if ([cookie.name isEqualToString:@"ct0"]) {
                    ct0 = cookie.value;
                } else if ([cookie.name isEqualToString:@"twid"]) {
                    twid = cookie.value;
                } else if ([cookie.name isEqualToString:@"auth_multi"]) {
                    authMulti = cookie.value;
                }
            }

            // A complete session needs all three. ct0 sometimes lands a beat after
            // auth_token; the poll timer retries until it does.
            if (authToken.length == 0 || ct0.length == 0 || twid.length == 0) {
                self.sessionCheckInFlight = NO;
                return;
            }

            [webView evaluateJavaScript:kWebLoginScannerJS
                      completionHandler:^(id result, __unused NSError* error) {
                          self.sessionCheckInFlight = NO;
                          if (self.finished || !self.view.window) return;
                          NSString* userID = [self userIDFromTwid:twid];
                          if (userID.length == 0) {
                              return;
                          }

                          NSString* username = nil;
                          if ([result isKindOfClass:[NSString class]] &&
                              [(NSString*)result hasPrefix:@"username:"]) {
                              username = [(NSString*)result substringFromIndex:9];
                          }

                          [self syncCookies:cookies];
                          [self finishWithUserID:userID
                                        username:username
                                       authToken:authToken
                                             ct0:ct0
                                            twid:twid
                                       authMulti:authMulti];
                      }];
        }];
}

// Copy the webview's cookies into the shared NSHTTPCookieStorage so the app's own
// NSURLSession stack (and WebCreateTweet.x's harvestSharedCookies) can read them.
- (void)syncCookies:(NSArray<NSHTTPCookie*>*)cookies {
    NSHTTPCookieStorage* storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie* cookie in cookies) {
        NSString* domain = cookie.domain ?: @"";
        if (![domain containsString:@"x.com"] && ![domain containsString:@"twitter.com"]) {
            continue;
        }
        [storage setCookie:cookie];
    }
}

- (NSString*)userIDFromTwid:(NSString*)twid {
    if (twid.length == 0) {
        return nil;
    }
    NSString* decoded = [twid stringByRemovingPercentEncoding] ?: twid;
    NSCharacterSet* nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSString* digits =
        [[decoded componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
    return digits.length ? digits : nil;
}

- (void)finishWithUserID:(NSString*)userID
                username:(NSString*)username
               authToken:(NSString*)authToken
                     ct0:(NSString*)ct0
                    twid:(NSString*)twid
               authMulti:(NSString*)authMulti {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    [self.pollTimer invalidate];
    self.pollTimer = nil;

    NSMutableDictionary<NSString*, NSString*>* pairs = [NSMutableDictionary dictionary];
    pairs[@"auth_token"] = authToken;
    pairs[@"ct0"] = ct0;
    pairs[@"twid"] = twid;
    if (authMulti.length) {
        pairs[@"auth_multi"] = authMulti;
    }

    // Hand the session to WebCreateTweet.x first: it caches the cookies, records the
    // account as cookie-login, and pre-warms the transaction-id generator so the very
    // first tweet/reply already has a valid x-client-transaction-id.
    webLoginDidCaptureCookies(userID, username, pairs);

    id account = [self registerNativeAccountForUserID:userID username:username authToken:authToken];

    void (^switchAndDismiss)(void) = ^{
        [self switchToAccount:account];
        UIViewController* presenting = self.presentingViewController;
        if (presenting) {
            [presenting dismissViewControllerAnimated:YES completion:nil];
        }
    };
    dispatch_async(dispatch_get_main_queue(), switchAndDismiss);
}

#pragma mark - Native account registration

// Register a dummy OAuth1 account in the native store so any code that reads the account's oauth token
// still recovers the correct userID.
- (id)registerNativeAccountForUserID:(NSString*)userID
                            username:(NSString*)username
                           authToken:(NSString*)authToken {
    Class accountCls = objc_getClass("TFNTwitterAccount");
    if (!accountCls) {
        return nil;
    }

    long long uid = userID.longLongValue;

    // If this account is already in the store, reuse it instead of adding a second copy.
    // (webLoginDidCaptureCookies already refreshed its cached cookies just above.)
    id existing = [self existingAccountForUserID:uid];
    if (existing) {
        return existing;
    }

    id account = accountWithUsernameAndUserID(accountCls, username ?: @"", uid);
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

    [self addAccountToStore:account];
    return account;
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

- (void)addAccountToStore:(id)account {
    if (!account) {
        return;
    }
    @try {
        Class twitterCls = objc_getClass("TFNTwitter");
        id shared = performShared(twitterCls, @selector(sharedTwitter));
        id service = performShared(shared, @selector(accountService));

        if (service && [service respondsToSelector:@selector(addAccount:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(service, @selector(addAccount:), account);
        }
        if ([twitterCls respondsToSelector:@selector(saveSharedTwitter)]) {
            ((void (*)(id, SEL))objc_msgSend)(twitterCls, @selector(saveSharedTwitter));
        }

        Class notifCls = objc_getClass("TFSAccountNotification");
        id name = performShared(notifCls, @selector(TFSAccountsDidChange));
        if ([name isKindOfClass:[NSString class]]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:name
                                                                object:shared
                                                              userInfo:nil];
        }
    } @catch (__unused NSException* exception) {
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
