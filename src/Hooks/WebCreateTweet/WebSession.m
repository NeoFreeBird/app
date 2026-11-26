#import "WebCreateTweetInternal.h"

static NSString* const WebQueryIDDefaultsKey = @"nfb_createtweet_queryid";
static NSString* WebCreateTweetQueryID = @"vwzfnq1lLOa1Nfx7htM2mw";
static NSString* const WebCreateNoteTweetQueryID = @"SZfgMjZCY6hPBEzJ4h0K9Q";

// MARK: - Session state

// Latest cookies harvested from the app's web session (the account currently signed in
// on the web). auth_multi carries the auth_token of every other signed-in account.
static NSString* WebCT0 = nil;
static NSString* WebAuthToken = nil;
static NSString* WebTwid = nil;
static NSString* WebAuthMulti = nil;

// accountCacheLock() protects both the latest cookie strings above and these
// per-account snapshots (userID -> @{auth_token, ct0, twid}).
static NSMutableDictionary<NSString*, NSDictionary*>* WebAccountCookies = nil;
static NSObject* WebAccountCookiesLock = nil;

static NSMutableSet<NSString*>* WebCookieLoginUserIDs = nil;
static NSString* const WebCookieLoginUsersKey = @"nfb_cookie_login_userids";

NSString* const BHTWebSessionUserAgent =
    @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
    @"(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

static NSString* const WebAccountCookiesKey = @"nfb_web_account_cookies";

BOOL BHTNativeCreateTweetInterceptEnabled(void) {
    return ![BHTSettings boolForKey:@"reply_in_webview"];
}

// twid is stored as "u=<id>" (percent-encoded). Pull the numeric account id out of it.
static NSString* userIDFromTwid(NSString* twid) {
    if (twid.length == 0) {
        return nil;
    }
    NSString* decoded = [twid stringByRemovingPercentEncoding] ?: twid;
    NSCharacterSet* nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSString* digits =
        [[decoded componentsSeparatedByCharactersInSet:nonDigits] componentsJoinedByString:@""];
    return digits.length ? digits : nil;
}

static NSString* userIDStringForAccount(id account) {
    if (!account || ![account respondsToSelector:@selector(userID)]) {
        return nil;
    }
    long long uid = ((long long (*)(id, SEL))objc_msgSend)(account, @selector(userID));
    return uid ? [@(uid) stringValue] : nil;
}

static NSObject* accountCacheLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WebAccountCookiesLock = [NSObject new];
        NSDictionary* saved =
            [[NSUserDefaults standardUserDefaults] dictionaryForKey:WebAccountCookiesKey];
        WebAccountCookies = [saved isKindOfClass:[NSDictionary class]] ? [saved mutableCopy]
                                                                       : [NSMutableDictionary dictionary];
    });
    return WebAccountCookiesLock;
}

static void cacheAccountPair(NSString* userID, NSDictionary* pair) {
    if (userID.length == 0) {
        return;
    }
    @synchronized(accountCacheLock()) {
        NSDictionary* previous = WebAccountCookies[userID];
        if (previous == pair || [previous isEqualToDictionary:pair]) {
            return;
        }
        if (pair) {
            WebAccountCookies[userID] = [pair copy];
        } else {
            [WebAccountCookies removeObjectForKey:userID];
        }
        [[NSUserDefaults standardUserDefaults] setObject:[WebAccountCookies copy]
                                                  forKey:WebAccountCookiesKey];
    }
}

static NSDictionary* cachedAccountPair(NSString* userID) {
    if (userID.length == 0) {
        return nil;
    }
    @synchronized(accountCacheLock()) {
        return WebAccountCookies[userID];
    }
}

static void storeSessionSnapshot(NSString* userID, NSString* authToken, NSString* ct0,
                                 NSString* twid, NSString* authMulti) {
    @synchronized(accountCacheLock()) {
        WebAuthToken = [authToken copy];
        WebCT0 = [ct0 copy];
        WebTwid = twid.length ? [twid copy] : [NSString stringWithFormat:@"u=%@", userID];
        WebAuthMulti = [authMulti copy];
        cacheAccountPair(userID, @{
            @"auth_token": WebAuthToken,
            @"ct0": WebCT0,
            @"twid": WebTwid,
        });
    }
}

void BHTStoreWebCookies(NSArray<NSHTTPCookie*>* cookies) {
    @synchronized(accountCacheLock()) {
        if (![cookies isKindOfClass:[NSArray class]]) {
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

            if ([cookie.name isEqualToString:@"ct0"]) {
                ct0 = [cookie.value copy];
            } else if ([cookie.name isEqualToString:@"auth_token"]) {
                authToken = [cookie.value copy];
            } else if ([cookie.name isEqualToString:@"twid"]) {
                twid = [cookie.value copy];
            } else if ([cookie.name isEqualToString:@"auth_multi"]) {
                authMulti = [cookie.value copy];
            }
        }

        NSString* userID = userIDFromTwid(twid);
        if (userID.length && authToken.length && ct0.length) {
            storeSessionSnapshot(userID, authToken, ct0, twid, authMulti);
        }
    }
}

void BHTHarvestSharedCookies(void) {
    static NSObject* harvestLock;
    static BOOL dirty = YES;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        harvestLock = [NSObject new];
        [[NSNotificationCenter defaultCenter]
            addObserverForName:NSHTTPCookieManagerCookiesChangedNotification
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification* note) {
                        @synchronized(harvestLock) {
                            dirty = YES;
                        }
                    }];
    });
    @synchronized(harvestLock) {
        if (!dirty) return;
        dirty = NO;
        NSMutableArray<NSHTTPCookie*>* all = [NSMutableArray array];
        for (NSString* domain in
             @[@"https://api.twitter.com", @"https://twitter.com", @"https://x.com", @"https://api.x.com"]) {
            NSArray* cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage]
                cookiesForURL:[NSURL URLWithString:domain]];
            if (cookies) [all addObjectsFromArray:cookies];
        }
        BHTStoreWebCookies(all);
    }
}

// MARK: - Cookie-login accounts

static void loadCookieLoginUsers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WebCookieLoginUserIDs = [NSMutableSet set];
        NSArray* saved = [[NSUserDefaults standardUserDefaults] arrayForKey:WebCookieLoginUsersKey];
        for (id uid in saved) {
            if ([uid isKindOfClass:[NSString class]]) {
                [WebCookieLoginUserIDs addObject:uid];
            }
        }
    });
}

// Whether this account uses cookie login rather than native OAuth credentials.
BOOL isCookieLoginUserID(NSString* userID) {
    if (userID.length == 0) {
        return NO;
    }
    loadCookieLoginUsers();
    @synchronized(WebCookieLoginUserIDs) {
        return [WebCookieLoginUserIDs containsObject:userID];
    }
}

static void markCookieLoginUserID(NSString* userID) {
    if (userID.length == 0) {
        return;
    }
    loadCookieLoginUsers();
    @synchronized(WebCookieLoginUserIDs) {
        if ([WebCookieLoginUserIDs containsObject:userID]) return;
        [WebCookieLoginUserIDs addObject:userID];
        [[NSUserDefaults standardUserDefaults] setObject:WebCookieLoginUserIDs.allObjects
                                                  forKey:WebCookieLoginUsersKey];
    }
}

void webLoginDidCaptureCookies(NSString* userID, __unused NSString* username,
                               NSDictionary<NSString*, NSString*>* cookiePairs) {
    if (userID.length == 0 || cookiePairs.count == 0) {
        return;
    }

    NSString* authToken = cookiePairs[@"auth_token"];
    NSString* ct0 = cookiePairs[@"ct0"];
    NSString* twid = cookiePairs[@"twid"];
    if (authToken.length == 0 || ct0.length == 0) {
        return;
    }

    storeSessionSnapshot(userID, authToken, ct0, twid, cookiePairs[@"auth_multi"]);

    markCookieLoginUserID(userID);
    BHTRefreshWebCookiesViaWebView();
}

NSString* BHTCreateTweetPath(void) {
    @synchronized(accountCacheLock()) {
        return [NSString stringWithFormat:@"/i/api/graphql/%@/CreateTweet", WebCreateTweetQueryID];
    }
}

NSString* BHTCreateNoteTweetPath(void) {
    return [NSString stringWithFormat:@"/i/api/graphql/%@/CreateNoteTweet", WebCreateNoteTweetQueryID];
}

// MARK: - Prewarm

void prewarmWebCookiesIfNeeded(void) {
    loadCookieLoginUsers();
    BOOL haveCookieLogin = NO;
    @synchronized(WebCookieLoginUserIDs) {
        haveCookieLogin = WebCookieLoginUserIDs.count > 0;
    }

    if (!haveCookieLogin && !BHTNativeCreateTweetInterceptEnabled() &&
        ![BHTSettings boolForKey:@"show_account_location"]) {
        return;
    }

    NSString* savedQueryID =
        [[NSUserDefaults standardUserDefaults] stringForKey:WebQueryIDDefaultsKey];
    if (savedQueryID.length) {
        @synchronized(accountCacheLock()) {
            WebCreateTweetQueryID = [savedQueryID copy];
        }
    }

    BHTRefreshWebCookiesViaWebView();
    BHTHarvestSharedCookies();
}

// MARK: - Credential resolution

static NSString* authTokenForUserID(NSString* userID) {
    @synchronized(accountCacheLock()) {
        if (userID.length == 0) {
            return nil;
        }

        NSString* primaryUID = userIDFromTwid(WebTwid);
        if ([primaryUID isEqualToString:userID] && WebAuthToken.length) {
            return WebAuthToken;
        }

        if (WebAuthMulti.length == 0) {
            return nil;
        }
        NSString* decoded = [WebAuthMulti stringByRemovingPercentEncoding] ?: WebAuthMulti;
        decoded = [decoded
            stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        NSCharacterSet* separators = [NSCharacterSet characterSetWithCharactersInString:@"|,"];
        for (NSString* entry in [decoded componentsSeparatedByCharactersInSet:separators]) {
            NSRange colon = [entry rangeOfString:@":"];
            if (colon.location == NSNotFound) {
                continue;
            }
            NSString* uid = [entry substringToIndex:colon.location];
            NSString* token = [entry substringFromIndex:NSMaxRange(colon)];
            if ([uid isEqualToString:userID] && token.length) {
                return token;
            }
        }
        return nil;
    }
}

@interface Ct0Fetcher : NSObject <NSURLSessionTaskDelegate>
@property (nonatomic, copy) NSString* ct0;
@property (nonatomic, copy) NSString* twid;
@property (nonatomic, assign) BOOL loggedOut;
- (void)captureFromResponse:(NSURLResponse*)response;
@end

@implementation Ct0Fetcher
- (void)captureFromResponse:(NSURLResponse*)response {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return;
    }
    NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
    NSArray<NSHTTPCookie*>* cookies =
        [NSHTTPCookie cookiesWithResponseHeaderFields:http.allHeaderFields
                                               forURL:http.URL ?: response.URL];
    for (NSHTTPCookie* cookie in cookies) {
        if ([cookie.name isEqualToString:@"ct0"] && cookie.value.length) {
            self.ct0 = [cookie.value copy];
        } else if ([cookie.name isEqualToString:@"twid"] && cookie.value.length) {
            self.twid = [cookie.value copy];
        }
    }
}
- (void)URLSession:(__unused NSURLSession*)session
                          task:(__unused NSURLSessionTask*)task
    willPerformHTTPRedirection:(NSHTTPURLResponse*)response
                    newRequest:(NSURLRequest*)request
             completionHandler:(void (^)(NSURLRequest*))completionHandler {
    [self captureFromResponse:response];

    NSString* target = request.URL.absoluteString.lowercaseString ?: @"";
    if ([target containsString:@"login"] || [target containsString:@"logout"] ||
        [target containsString:@"/i/flow/"] || [target containsString:@"account/access"]) {
        self.loggedOut = YES;
    }
    completionHandler(request);
}
@end

// Mint a fresh ct0 for a bare auth_token by hitting x.com once and reading the Set-Cookie.
static NSString* fetchCt0Sync(NSString* authToken, NSString* expectedUserID) {
    if (authToken.length == 0 || [NSThread isMainThread]) {
        return nil;
    }

    Ct0Fetcher* fetcher = [Ct0Fetcher new];
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    NSURLSession* session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:fetcher
                                                     delegateQueue:nil];

    NSMutableURLRequest* request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://x.com/"]];
    request.HTTPShouldHandleCookies = NO;
    [request setValue:[NSString stringWithFormat:@"auth_token=%@", authToken]
        forHTTPHeaderField:@"Cookie"];
    [request setValue:BHTWebSessionUserAgent forHTTPHeaderField:@"User-Agent"];

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request
                completionHandler:^(__unused NSData* data, NSURLResponse* response,
                                    __unused NSError* error) {
                    [fetcher captureFromResponse:response];
                    dispatch_semaphore_signal(done);
                }] resume];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)))) {
        [session invalidateAndCancel];
        return nil;
    }
    [session finishTasksAndInvalidate];

    if (fetcher.loggedOut) {
        return nil;
    }

    NSString* responseUserID = userIDFromTwid(fetcher.twid);
    if (expectedUserID.length && responseUserID.length &&
        ![responseUserID isEqualToString:expectedUserID]) {
        return nil;
    }
    return fetcher.ct0;
}

BOOL BHTResolveWebCredentials(NSString* userID, NSString** outAuthToken, NSString** outCt0) {
    static NSMutableDictionary<NSString*, dispatch_group_t>* refreshes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ refreshes = [NSMutableDictionary dictionary]; });

    NSDictionary* cached;
    NSString* authToken;
    dispatch_group_t refresh = nil;
    BOOL ownsRefresh = NO;
    @synchronized(accountCacheLock()) {
        cached = cachedAccountPair(userID);
        authToken = cached[@"auth_token"] ?: authTokenForUserID(userID);
        if (!authToken.length) return NO;
        if (![cached[@"ct0"] length]) {
            if ([NSThread isMainThread]) return NO;
            refresh = refreshes[userID];
            if (!refresh) {
                refresh = dispatch_group_create();
                dispatch_group_enter(refresh);
                refreshes[userID] = refresh;
                ownsRefresh = YES;
            }
        }
    }

    if (ownsRefresh) {
        NSString* ct0 = fetchCt0Sync(authToken, userID);
        @synchronized(accountCacheLock()) {
            NSDictionary* latest = cachedAccountPair(userID);
            NSString* latestAuth = latest[@"auth_token"] ?: authTokenForUserID(userID);
            // A login may have replaced this session while the fetch was running.
            if (ct0.length && [latestAuth isEqualToString:authToken] && ![latest[@"ct0"] length]) {
                cacheAccountPair(userID, @{
                    @"auth_token": authToken,
                    @"ct0": ct0,
                    @"twid": latest[@"twid"] ?: [NSString stringWithFormat:@"u=%@", userID],
                });
            }
            [refreshes removeObjectForKey:userID];
            dispatch_group_leave(refresh);
        }
    } else if (refresh) {
        if (dispatch_group_wait(refresh, dispatch_time(DISPATCH_TIME_NOW, 16 * NSEC_PER_SEC))) {
            return NO;
        }
    }

    if (refresh) cached = cachedAccountPair(userID);
    if (![cached[@"auth_token"] length] || ![cached[@"ct0"] length]) return NO;
    if (outAuthToken) *outAuthToken = cached[@"auth_token"];
    if (outCt0) *outCt0 = cached[@"ct0"];
    return YES;
}

// MARK: - Shared account accessor

id accountForAuthenticatedWebView(void) {
    Class hostClass = NSClassFromString(@"T1HostViewController");
    if ([hostClass respondsToSelector:@selector(sharedHostViewController)]) {
        id host = [hostClass sharedHostViewController];
        if ([host respondsToSelector:@selector(currentAccount)]) {
            id account = [host currentAccount];
            if (account) {
                return account;
            }
        }
    }
    return nil;
}

// The current web session's auth_token + ct0, for read-only web GraphQL GETs (e.g.
// SourceLabels.x). Harvests the shared cookie jar first; nil until a session exists.
NSDictionary* currentWebCredentials(void) {
    BHTHarvestSharedCookies();
    @synchronized(accountCacheLock()) {
        if (WebAuthToken.length == 0 || WebCT0.length == 0) return nil;
        return @{@"auth_token": WebAuthToken, @"ct0": WebCT0};
    }
}

// A cookie-login account's cached web session. Never blocks: a missing ct0 is fine,
// since x.com mints one on the first authenticated page load.
NSDictionary* BHTCachedWebSessionForUserID(NSString* userID) {
    if (!isCookieLoginUserID(userID)) {
        return nil;
    }

    NSDictionary* cached = cachedAccountPair(userID);
    NSString* authToken = cached[@"auth_token"];
    NSString* ct0 = cached[@"ct0"];
    if (authToken.length == 0) {
        authToken = authTokenForUserID(userID);
        ct0 = nil;
    }
    if (authToken.length == 0) {
        return nil;
    }

    NSString* twid = cached[@"twid"];
    return @{
        @"auth_token": authToken,
        @"ct0": ct0 ?: @"",
        @"twid": twid.length ? twid : [NSString stringWithFormat:@"u=%@", userID],
    };
}

NSDictionary* BHTCachedWebSessionForAccount(id account) {
    return BHTCachedWebSessionForUserID(userIDStringForAccount(account));
}

// Query IDs and credential snapshots share the account-cache lock.
NSString* BHTCurrentWebUserID(void) {
    @synchronized(accountCacheLock()) {
        return userIDFromTwid(WebTwid);
    }
}

void BHTUpdateCreateTweetQueryID(NSString* queryID) {
    @synchronized(accountCacheLock()) {
        if (queryID.length && ![queryID isEqualToString:WebCreateTweetQueryID]) {
            WebCreateTweetQueryID = [queryID copy];
            [[NSUserDefaults standardUserDefaults] setObject:queryID forKey:WebQueryIDDefaultsKey];
        }
    }
}

void BHTInvalidateWebCredentials(NSString* userID, NSURLRequest* request) {
    @synchronized(accountCacheLock()) {
        NSDictionary* pair = cachedAccountPair(userID);
        NSString* sentCT0 = [request valueForHTTPHeaderField:@"x-csrf-token"];
        NSString* sentCookies = [request valueForHTTPHeaderField:@"Cookie"];
        NSString* authToken = pair[@"auth_token"];
        NSString* tokenCookie = [NSString stringWithFormat:@"auth_token=%@", authToken];
        if (authToken.length && [pair[@"ct0"] isEqualToString:sentCT0] &&
            [[sentCookies componentsSeparatedByString:@"; "] containsObject:tokenCookie]) {
            cacheAccountPair(userID, @{@"auth_token": authToken, @"twid": pair[@"twid"] ?: @""});
        }
    }
}

static BOOL isUsableCookiePair(NSDictionary* pair) {
    return [pair[@"auth_token"] length] > 0 && [pair[@"ct0"] length] > 0;
}

// The session cookies used to seed the helper webview. The global session is only filled from the shared
// cookie jar, which can be empty at launch, so fall back to a persisted per-account pair (the ones request
// signing uses), cookie-login accounts first. A helper with no session is redirected to the logged-out
// onboarding page, where the transaction id module never loads.
NSDictionary* BHTCurrentWebSessionCookies(void) {
    @synchronized(accountCacheLock()) {
        NSDictionary* current =
            @{@"auth_token": WebAuthToken ?: @"", @"ct0": WebCT0 ?: @"", @"twid": WebTwid ?: @""};
        if (isUsableCookiePair(current)) {
            return current;
        }

        loadCookieLoginUsers();
        NSDictionary* fallback = nil;
        @synchronized(WebCookieLoginUserIDs) {
            for (NSString* userID in WebCookieLoginUserIDs) {
                if (isUsableCookiePair(WebAccountCookies[userID])) {
                    fallback = WebAccountCookies[userID];
                    break;
                }
            }
        }
        for (NSDictionary* pair in WebAccountCookies.allValues) {
            if (fallback) break;
            if (isUsableCookiePair(pair)) fallback = pair;
        }
        return fallback ?: current;
    }
}
