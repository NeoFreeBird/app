#import "WebCreateTweetInternal.h"

static const void* WebPostingUIDKey = &WebPostingUIDKey;
static const void* CreateTweetWatcherKey = &CreateTweetWatcherKey;

// MARK: - Request transform

static BOOL isCreateTweetURL(NSURL* url) {
    return url && ([url.path hasSuffix:@"/CreateTweet"] ||
                   [url.path hasSuffix:@"/CreateNoteTweet"]);
}

static BOOL isAccountURL(NSURL* url) { return url && ([url.path containsString:@"/1.1/account"] || [url.path containsString:@"/1.1/users/"]); }

static BOOL isPeriscopeAuthURL(NSURL* url) {
    NSString* path = url.path ?: @"";
    return [path hasSuffix:@"/oauth/authenticate_periscope"] ||
           [path hasSuffix:@"/oauth/authenticate_periscope.json"];
}

static BOOL isMuteURL(NSURL* url) { return url && [url.path containsString:@"/1.1/mutes"]; }

static BOOL isGrokURL(NSURL* url) { return url && [url.path containsString:@"/2/grok"]; }

static BOOL isTonMediaURL(NSURL* url) {
    return [url.host.lowercaseString isEqualToString:@"ton.x.com"] &&
           [url.path hasPrefix:@"/i/ton/data/xchat_media/"];
}

// These paths need to go through the web path, otherwise AppAttest kicks in
static BOOL isWriteRequest(NSURL* url) {
    return isCreateTweetURL(url) || isAccountURL(url) || isPeriscopeAuthURL(url) ||
           isMuteURL(url) || isGrokURL(url) || isTonMediaURL(url);
}

static NSURL* webEquivalentURL(NSURL* url) {
    if (!isWriteRequest(url)) {
        return url;
    }

    NSURLComponents* c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (c && [url.path hasSuffix:@"/CreateNoteTweet"]) {
        c.host = @"x.com";
        c.path = BHTCreateNoteTweetPath();
        return c.URL ?: url;
    }
    if (c && isPeriscopeAuthURL(url)) {
        c.host = @"x.com";
        c.path = @"/i/api/1.1/oauth/authenticate_periscope.json";
        return c.URL ?: url;
    }
    if (c && isMuteURL(url)) {
        c.host = @"x.com";
        c.path = [@"/i/api" stringByAppendingString:[c.path substringFromIndex:[c.path rangeOfString:@"/1.1/mutes"].location]];
        return c.URL ?: url;
    }
    NSString* path = c.path ?: @"";
    if (c && [path containsString:@"/graphql/"]) {
        c.host = @"x.com";
        if (![path hasPrefix:@"/i/api/"]) {
            NSRange g = [path rangeOfString:@"/graphql/"];
            c.path = [@"/i/api" stringByAppendingString:[path substringFromIndex:g.location]];
        }
        return c.URL ?: url;
    }
    return url;
}

// The queryId sits in the request path: .../graphql/<queryId>/CreateTweet
static NSString* queryIDFromCreateTweetURL(NSURL* url) {
    NSArray<NSString*>* components = url.path.pathComponents;
    if (components.count >= 2 && [components.lastObject isEqualToString:@"CreateTweet"]) {
        return components[components.count - 2];
    }
    return nil;
}

// The native request signs with OAuth: oauth_token="<userID>-<secret>".
static NSString* postingUserIDFromRequest(NSURLRequest* request) {
    NSString* auth = [request valueForHTTPHeaderField:@"Authorization"];
    if (![auth isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSRange marker = [auth rangeOfString:@"oauth_token=\""];
    if (marker.location == NSNotFound) {
        return nil;
    }
    NSString* rest = [auth substringFromIndex:NSMaxRange(marker)];
    NSRange endQuote = [rest rangeOfString:@"\""];
    if (endQuote.location == NSNotFound) {
        return nil;
    }
    NSString* token = [rest substringToIndex:endQuote.location];
    NSRange dash = [token rangeOfString:@"-"];
    return dash.location != NSNotFound ? [token substringToIndex:dash.location] : nil;
}

// Replace the (invalid, placeholder) native OAuth with the web session's cookie auth.
static void applyWebAuth(NSMutableURLRequest* request, NSString* authToken, NSString* ct0,
                         NSString* userID) {
    request.HTTPShouldHandleCookies = NO;

    BOOL isWrite = isWriteRequest(request.URL);
    NSArray<NSString*>* headersToStrip = isWrite
                                             ? @[
                                                   @"Authorization", @"X-Twitter-Client-DeviceID", @"X-Twitter-Client-Version",
                                                   @"X-Twitter-Client", @"X-Twitter-API-Version", @"X-Twitter-Client-Limit-Ad-Tracking",
                                                   @"X-B3-TraceId", @"Timezone", @"kdt", @"X-Client-UUID", @"Host"
                                               ]
                                             : @[@"Authorization", @"X-B3-TraceId", @"Host"];
    for (NSString* header in headersToStrip) {
        [request setValue:nil forHTTPHeaderField:header];
    }

    // Reads present the app bearer (native timeline semantics); the write presents the
    // web bearer its transaction id is minted for.
    [request setValue:isWrite ? WebClientBearer : NativeClientBearer forHTTPHeaderField:@"authorization"];
    if (isWrite) {
        [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
        [request setValue:@"yes" forHTTPHeaderField:@"x-twitter-active-user"];
        if ([request.URL.host isEqualToString:@"api.twitter.com"]) {
            NSURLComponents* c = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
            c.host = @"api.x.com";
            request.URL = c.URL;
        }
    }
    if (ct0.length) {
        [request setValue:ct0 forHTTPHeaderField:@"x-csrf-token"];
    }

    NSMutableArray<NSString*>* cookiePairs = [NSMutableArray array];
    if (authToken.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"auth_token=%@", authToken]];
    }
    if (ct0.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"ct0=%@", ct0]];
    }
    if (userID.length) {
        [cookiePairs addObject:[NSString stringWithFormat:@"twid=u%%3D%@", userID]];
    }
    [request setValue:[cookiePairs componentsJoinedByString:@"; "] forHTTPHeaderField:@"Cookie"];
}

// Check if the request is using native OAuth, so that it can be replaced
static BOOL requestUsesNativeOAuth(NSURLRequest* request) {
    NSString* auth = [request valueForHTTPHeaderField:@"Authorization"]
                         ?: [request valueForHTTPHeaderField:@"authorization"];
    return [auth isKindOfClass:[NSString class]] && [auth containsString:@"oauth_token="];
}

NSMutableURLRequest* BHTWebRequestFromNativeSend(NSURLRequest* request) {
    NSURL* url = request.URL;
    if (!url) {
        return nil;
    }

    BOOL isCreateTweet = isCreateTweetURL(url);
    BOOL createTweetReroute = isCreateTweet && BHTNativeCreateTweetInterceptEnabled();

    NSString* postingUserID = postingUserIDFromRequest(request);
    BOOL tonCredentialInjection = isTonMediaURL(url);
    BOOL nativeOAuth = requestUsesNativeOAuth(request);
    if (postingUserID.length == 0 && (nativeOAuth || tonCredentialInjection)) {
        postingUserID = BHTCurrentWebUserID();
    }
    BOOL cookieReplication = nativeOAuth && isCookieLoginUserID(postingUserID);

    if (!createTweetReroute && !cookieReplication && !tonCredentialInjection) {
        return nil;
    }
    if (postingUserID.length == 0) {
        return nil;
    }

    if (isCreateTweet) {
        NSString* queryID = queryIDFromCreateTweetURL(url);
        BHTUpdateCreateTweetQueryID(queryID);
    }

    BHTHarvestSharedCookies();

    NSString *authToken = nil, *ct0 = nil;
    if (!BHTResolveWebCredentials(postingUserID, &authToken, &ct0)) {
        return nil;
    }

    NSMutableURLRequest* outgoing = [request mutableCopy];

    outgoing.URL = webEquivalentURL(outgoing.URL);
    if (isPeriscopeAuthURL(outgoing.URL)) {
        outgoing.HTTPMethod = @"GET";
        outgoing.HTTPBody = nil;
    }
    applyWebAuth(outgoing, authToken, ct0, postingUserID);

    // Web writes are routed to the web endpoint and carry a transaction id; reads
    // stay native and never need one.
    NSString* token = isWriteRequest(outgoing.URL) ? BHTTransactionIDForRequest(outgoing) : nil;
    if (token.length) {
        [outgoing setValue:token forHTTPHeaderField:@"x-client-transaction-id"];
    } else if (isCreateTweet) {
        return nil;
    }

    if (isCreateTweet) {
        objc_setAssociatedObject(outgoing, WebPostingUIDKey, postingUserID,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return outgoing;
}

// MARK: - Task watcher

@interface CreateTweetWatcher : NSObject
@property (nonatomic, copy) NSString* userID;
@end

@implementation CreateTweetWatcher
- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(__unused NSDictionary*)change
                       context:(__unused void*)context {
    NSURLSessionTask* task = object;
    if (![keyPath isEqualToString:@"state"] || task.state != NSURLSessionTaskStateCompleted) {
        return;
    }

    CreateTweetWatcher* keepAlive = self; // survive detaching our own retainer below
    @try {
        [task removeObserver:self forKeyPath:@"state"];
    } @catch (__unused NSException* exception) {
    }
    objc_setAssociatedObject(task, CreateTweetWatcherKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSInteger code = [task.response isKindOfClass:[NSHTTPURLResponse class]]
                         ? [(NSHTTPURLResponse*)task.response statusCode]
                         : 0;
    // Only authentication failures invalidate CSRF. Rate limits and rejected tweet
    // contents should not force another session refresh. Ignore stale failures.
    if ((code == 401 || code == 403) && keepAlive.userID.length) {
        BHTInvalidateWebCredentials(keepAlive.userID, task.originalRequest);
    }
}
@end

void BHTWatchCreateTweetTask(id task, NSURLRequest* request) {
    NSString* userID = objc_getAssociatedObject(request, WebPostingUIDKey);
    if (![task isKindOfClass:[NSURLSessionTask class]] || userID.length == 0) {
        return;
    }
    CreateTweetWatcher* watcher = [CreateTweetWatcher new];
    watcher.userID = userID;
    objc_setAssociatedObject(task, CreateTweetWatcherKey, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        [task addObserver:watcher
               forKeyPath:@"state"
                  options:NSKeyValueObservingOptionNew
                  context:NULL];
    } @catch (__unused NSException* exception) {
    }
}

static BOOL replaceTaskRequest(NSURLSessionTask* task, NSURLRequest* request) {
    @try {
        [task setValue:request forKey:@"originalRequest"];
        [task setValue:request forKey:@"currentRequest"];
    } @catch (__unused NSException* exception) {
        return NO;
    }
    return task.currentRequest == request;
}

void BHTPrepareWebTaskForResume(NSURLSessionTask* task) {
    NSURLRequest* request = task.currentRequest ?: task.originalRequest;
    BOOL tonMediaRequest = isTonMediaURL(request.URL);
    BOOL grokOAuthRequest = isGrokURL(request.URL) && requestUsesNativeOAuth(request);
    if (task.state == NSURLSessionTaskStateSuspended && (tonMediaRequest || grokOAuthRequest)) {
        NSMutableURLRequest* outgoing = BHTWebRequestFromNativeSend(request);
        if (outgoing) {
            replaceTaskRequest(task, outgoing);
        }
    }
}
