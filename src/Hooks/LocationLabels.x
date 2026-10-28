//
//  LocationLabels.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Restore Tweet Source Labels / Account Locations
//
// The author's "based in" country does not survive in the on-device
// status models, so this is fetched from x.com's web GraphQL endpoints (reusing the
// web session that WebCreateTweet.x establishes), cached, and appended to the detail
// footer item's time string. Original idea by @nyaathea; the account-location half
// mirrors what Control Panel for Twitter does on the web.


// Account locations keyed by screen name.
static NSMutableDictionary* accountLocations = nil;
static NSMutableDictionary* locationPending = nil;
static NSMutableDictionary* locationRetries = nil;

static char kFooterComposedKey;
static char kFooterTweetIDKey;    // the tweet ID a footer text view is currently showing
static char kFooterScreenNameKey; // the author handle a footer text view is currently showing
static char kFooterObservingKey;  // whether a footer text view registered for update notifications

#define LOCATION_NOTE         @"AccountLocationUpdated"
#define MAX_SOURCE_CACHE_SIZE 200
#define MAX_FETCH_RETRIES     3

// Public web bearer token (not a secret; ships in the web client).
static NSString* const kSourceBearer = @"Bearer "
                                       @"AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puT"
                                       @"s%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA";

static NSString* const kAboutAccountQueryID = @"XRqGa7EeokUU5kppkh13EA";

// JSON-serialize `object` and percent-encode it for a GraphQL query parameter.
static NSString* encodedQueryParameter(id object) {
    NSData* data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return nil;

    NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [json
        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
}

// Dictionary-typed subscript that tolerates missing, NSNull and mistyped nodes — a
// GraphQL response nulls out whole branches for suspended or nonexistent accounts.
static NSDictionary* dictionaryValue(id container, NSString* key) {
    if (![container isKindOfClass:[NSDictionary class]]) return nil;

    id value = container[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSMutableURLRequest* webGraphQLRequest(NSURL* url) {
    if (!url) return nil;

    NSDictionary* credentials = currentWebCredentials();
    NSString* authToken = credentials[@"auth_token"];
    NSString* ct0 = credentials[@"ct0"];
    if (authToken.length == 0 || ct0.length == 0) return nil;

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 10.0;
    request.HTTPShouldHandleCookies = NO;
    [request setValue:kSourceBearer forHTTPHeaderField:@"authorization"];
    [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
    [request setValue:@"yes" forHTTPHeaderField:@"x-twitter-active-user"];
    [request setValue:@"en" forHTTPHeaderField:@"x-twitter-client-language"];
    [request setValue:ct0 forHTTPHeaderField:@"x-csrf-token"];
    [request setValue:[NSString stringWithFormat:@"auth_token=%@; ct0=%@", authToken, ct0]
        forHTTPHeaderField:@"Cookie"];
    return request;
}

// Decodes a 200 response body, or nil if the request failed in any way.
static NSDictionary* jsonFromResponse(NSData* data, NSURLResponse* response, NSError* error) {
    NSHTTPURLResponse* http =
        [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)response : nil;
    if (error || !data || http.statusCode != 200) return nil;

    NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

static void pruneCache(NSMutableDictionary* cache, NSString* unavailable,
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

static NSString* displayableValue(NSString* cached, NSString* unavailable) {
    if (cached.length == 0 || [cached isEqualToString:unavailable]) return nil;
    return cached;
}

// --- Model / view seams verified against classdump/12.3 (T1Twitter.c) ---

@interface T1ConversationFooterItem : NSObject
@property (nonatomic, copy) NSString* timeAgo;
@end

@interface T1ConversationFooterTextView (SourceLabels)
@property (nonatomic, readonly) T1ConversationFooterItem* footerItem;
@property (nonatomic, readonly) TFNAttributedTextView* textView;
- (void)BHT_forceRecolorSource;
- (void)BHT_startObservingFooterUpdates;
- (void)BHT_composeFooterSuffixWithLocation:(NSString*)location;
@end

@interface TFNAttributedTextView (SourceLabels)
- (TFNAttributedTextModel*)textModel;
@end

@interface AccountLocationHelper : NSObject
+ (NSString*)unavailableString;
+ (void)fetchLocationForScreenName:(NSString*)screenName;
+ (NSURL*)aboutAccountURLForScreenName:(NSString*)screenName;
+ (NSString*)labelFromAboutAccount:(NSDictionary*)json;
+ (void)markScreenName:(NSString*)screenName
           unavailable:(BOOL)unavailable
          withLocation:(NSString*)location;
+ (void)retryOrFailScreenName:(NSString*)screenName;
@end

@implementation AccountLocationHelper

+ (NSString*)unavailableString {
    return [[BHTBundle sharedBundle] localizedStringForKey:@"LOCATION_UNAVAILABLE"];
}

+ (NSURL*)aboutAccountURLForScreenName:(NSString*)screenName {
    NSString* encodedVariables = encodedQueryParameter(@{@"screenName": screenName});
    if (encodedVariables.length == 0) {
        return nil;
    }

    NSString* urlString =
        [NSString stringWithFormat:@"https://x.com/i/api/graphql/%@/AboutAccountQuery?variables=%@",
                                   kAboutAccountQueryID, encodedVariables];
    return [NSURL URLWithString:urlString];
}

+ (NSString*)labelFromAboutAccount:(NSDictionary*)json {
    NSDictionary* result =
        dictionaryValue(dictionaryValue(dictionaryValue(json, @"data"),
                                        @"user_result_by_screen_name"),
                        @"result");
    NSDictionary* about = dictionaryValue(result, @"about_profile");

    NSString* basedIn = about[@"account_based_in"];
    if (![basedIn isKindOfClass:[NSString class]] || basedIn.length == 0) return nil;

    if (![about[@"location_accurate"] boolValue]) {
        return [basedIn stringByAppendingString:@"?"];
    }
    return basedIn;
}

+ (void)markScreenName:(NSString*)screenName
           unavailable:(BOOL)unavailable
          withLocation:(NSString*)location {
    dispatch_async(dispatch_get_main_queue(), ^{
        [locationPending removeObjectForKey:screenName];

        if (unavailable) {
            accountLocations[screenName] = [self unavailableString];
        } else {
            accountLocations[screenName] = location;
            [locationRetries removeObjectForKey:screenName];
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:LOCATION_NOTE
                                                            object:nil
                                                          userInfo:@{@"screenName": screenName}];
    });
}

+ (void)retryOrFailScreenName:(NSString*)screenName {
    dispatch_async(dispatch_get_main_queue(), ^{
        [locationPending removeObjectForKey:screenName];

        NSInteger retries = [locationRetries[screenName] integerValue];
        if (retries >= MAX_FETCH_RETRIES) {
            [self markScreenName:screenName unavailable:YES withLocation:nil];
            return;
        }

        locationRetries[screenName] = @(retries + 1);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [self fetchLocationForScreenName:screenName];
                       });
    });
}

// Must be called on the main thread.
+ (void)fetchLocationForScreenName:(NSString*)screenName {
    if (screenName.length == 0) return;

    NSString* unavailable = [self unavailableString];
    pruneCache(accountLocations, unavailable, locationPending, locationRetries);

    if ([locationPending[screenName] boolValue]) return;

    NSString* existing = accountLocations[screenName];
    if (existing.length > 0 && ![existing isEqualToString:unavailable]) return;

    NSMutableURLRequest* request = webGraphQLRequest([self aboutAccountURLForScreenName:screenName]);
    if (!request) {
        [self retryOrFailScreenName:screenName];
        return;
    }

    locationPending[screenName] = @(YES);

    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
              NSDictionary* json = jsonFromResponse(data, response, error);
              if (!json) {
                  [self retryOrFailScreenName:screenName];
                  return;
              }

              NSString* location = [self labelFromAboutAccount:json];
              if (location.length == 0) {
                  [self markScreenName:screenName unavailable:YES withLocation:nil];
                  return;
              }

              [self markScreenName:screenName unavailable:NO withLocation:location];
          }];
    [task resume];
}

@end

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

// The status model exposes the author handle either directly or via an author object,
// depending on how the timeline built it, so probe both.
static NSString* screenNameFromStatus(id status) {
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

// MARK: - Footer injection
//
// -updateFooterTextView rebuilds the footer text from footerItem.timeAgo, so the
// source and location are appended there before %orig; when either arrives async we
// just re-run it.

%hook T1ConversationFooterTextView

- (void)updateFooterTextView {
    BOOL wantsLocation = [BHTSettings boolForKey:@"show_account_location"];

    if (!wantsLocation) {
        %orig;
        return;
    }

    @try {
        id viewModel = self.viewModel;
        id status = [viewModel respondsToSelector:@selector(tweet)]
                        ? [viewModel performSelector:@selector(tweet)]
                        : nil;

        NSString* tweetID = nil;
        if ([status respondsToSelector:@selector(statusID)]) {
            long long statusID = [(TFNTwitterStatus*)status statusID];
            if (statusID > 0) tweetID = [NSString stringWithFormat:@"%lld", statusID];
        }

        NSString* screenName = wantsLocation ? screenNameFromStatus(status) : nil;

        objc_setAssociatedObject(self, &kFooterTweetIDKey, tweetID,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &kFooterScreenNameKey, screenName,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        if (tweetID.length > 0 || screenName.length > 0) {
            [self BHT_startObservingFooterUpdates];
        }


        NSString* location = nil;
        if (wantsLocation && screenName.length > 0) {
            NSString* cached = accountLocations[screenName];
            if (cached == nil) {
                accountLocations[screenName] = @"";
                [AccountLocationHelper fetchLocationForScreenName:screenName];
            }
            location = displayableValue(cached, [AccountLocationHelper unavailableString]);
        }

        [self BHT_composeFooterSuffixWithLocation:location];
    } @catch (__unused NSException* e) {
    }

    %orig;
}

// Rewrites timeAgo as "<time> · <location>", keeping the order stable no
// matter which of the two fetches resolves first.
%new
- (void)BHT_composeFooterSuffixWithLocation:(NSString*)location {
    T1ConversationFooterItem* footerItem = self.footerItem;
    NSString* current = footerItem.timeAgo;
    if (!footerItem || current.length == 0) return;

    NSArray* previous = objc_getAssociatedObject(footerItem, &kFooterComposedKey);
    NSString* base = [previous.lastObject isEqualToString:current] ? previous.firstObject : current;

    NSMutableString* composed = [base mutableCopy];
    if (location.length > 0) [composed appendFormat:@" · %@", location];

    if (![composed isEqualToString:current]) {
        footerItem.timeAgo = composed;
    }
    objc_setAssociatedObject(footerItem, &kFooterComposedKey, @[base, [composed copy]],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)BHT_startObservingFooterUpdates {
    if ([objc_getAssociatedObject(self, &kFooterObservingKey) boolValue]) return;

    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(accountLocationUpdated:)
                   name:LOCATION_NOTE
                 object:nil];
    objc_setAssociatedObject(self, &kFooterObservingKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)accountLocationUpdated:(NSNotification*)notification {
    NSString* screenName = notification.userInfo[@"screenName"];
    NSString* mine = objc_getAssociatedObject(self, &kFooterScreenNameKey);
    if (screenName.length > 0 && [screenName isEqualToString:mine]) {
        [self updateFooterTextView];
        [self setNeedsDisplay];
        [self setNeedsLayout];
    }
}

- (void)dealloc {
    if ([objc_getAssociatedObject(self, &kFooterObservingKey) boolValue]) {
        NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
        [center removeObserver:self name:LOCATION_NOTE object:nil];
    }
    %orig;
}

%end

%ctor {
    if (!accountLocations) accountLocations = [NSMutableDictionary dictionary];
    if (!locationPending) locationPending = [NSMutableDictionary dictionary];
    if (!locationRetries) locationRetries = [NSMutableDictionary dictionary];

    %init;
}