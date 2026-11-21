#import "LocationLabels.h"

// MARK: - Restore Tweet Source Labels / Account Locations
//
// The author's "based in" country does not survive in the on-device
// status models, so this is fetched from x.com's web GraphQL endpoint (reusing the
// web session that WebCreateTweet.x establishes), cached, and appended to the detail
// footer item's time string. Original idea by @nyaathea; the account-location part
// mirrors what Control Panel for Twitter does on the web.

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
