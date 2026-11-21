#import "LocationLabels.h"

// Remove any special characters (mainly the @ prefix, which was causing all requests to silently fail)
static NSString* normalizedScreenName(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;

    static NSCharacterSet* nonHandleCharacters = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        nonHandleCharacters = [[NSCharacterSet
            characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxy"
                                               @"z0123456789_"] invertedSet];
    });

    NSString* name = [value stringByTrimmingCharactersInSet:nonHandleCharacters];
    return name.length > 0 ? name : nil;
}

// JSON-serialize `object` and percent-encode it for a GraphQL query parameter.
NSString* encodedQueryParameter(id object) {
    NSData* data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return nil;

    NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [json
        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
}

// Dictionary-typed subscript that tolerates missing, NSNull and mistyped nodes — a
// GraphQL response nulls out whole branches for suspended or nonexistent accounts.
NSDictionary* dictionaryValue(id container, NSString* key) {
    if (![container isKindOfClass:[NSDictionary class]]) return nil;

    id value = container[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

NSMutableURLRequest* webGraphQLRequest(NSURL* url) {
    if (!url) return nil;

    NSDictionary* credentials = currentWebCredentials();
    NSString* authToken = credentials[@"auth_token"];
    NSString* ct0 = credentials[@"ct0"];
    if (authToken.length == 0 || ct0.length == 0) return nil;

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 10.0;
    request.HTTPShouldHandleCookies = NO;
    [request setValue:WebClientBearer forHTTPHeaderField:@"authorization"];
    [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
    [request setValue:@"yes" forHTTPHeaderField:@"x-twitter-active-user"];
    [request setValue:@"en" forHTTPHeaderField:@"x-twitter-client-language"];
    [request setValue:ct0 forHTTPHeaderField:@"x-csrf-token"];
    [request setValue:[NSString stringWithFormat:@"auth_token=%@; ct0=%@", authToken, ct0]
        forHTTPHeaderField:@"Cookie"];
    return request;
}

// Decodes a 200 response body, or nil if the request failed in any way.
NSDictionary* jsonFromResponse(NSData* data, NSURLResponse* response, NSError* error) {
    NSHTTPURLResponse* http =
        [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)response : nil;
    if (error || !data || http.statusCode != 200) return nil;

    NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

void pruneCache(NSMutableDictionary* cache, NSString* unavailable,
                NSMutableDictionary* pending, NSMutableDictionary* retries) {
    if (cache.count <= MAX_SOURCE_CACHE_SIZE) return;

    NSMutableArray* keysToRemove = [NSMutableArray array];
    for (NSString* key in cache) {
        NSString* value = cache[key];
        if (value.length == 0 || [value isEqualToString:unavailable]) {
            [keysToRemove addObject:key];
        }
    }

    for (NSString* key in keysToRemove) {
        [cache removeObjectForKey:key];
        [pending removeObjectForKey:key];
        [retries removeObjectForKey:key];
    }
}

NSString* displayableValue(NSString* cached, NSString* unavailable) {
    if (cached.length == 0 || [cached isEqualToString:unavailable]) return nil;
    return cached;
}

NSString* screenNameFromStatus(id status) {
    if (!status) return nil;

    if ([status respondsToSelector:@selector(fromUserName)]) {
        NSString* name = normalizedScreenName([status performSelector:@selector(fromUserName)]);
        if (name) return name;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    for (NSString* authorKey in @[@"author", @"fromUser", @"user"]) {
        SEL authorSelector = NSSelectorFromString(authorKey);
        if (![status respondsToSelector:authorSelector]) continue;

        id author = [status performSelector:authorSelector];
        for (NSString* nameKey in @[@"screenName", @"username"]) {
            SEL nameSelector = NSSelectorFromString(nameKey);
            if (![author respondsToSelector:nameSelector]) continue;

            NSString* name = normalizedScreenName([author performSelector:nameSelector]);
            if (name) return name;
        }
    }
#pragma clang diagnostic pop

    return nil;
}
