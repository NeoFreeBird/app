//
//  LinkTracking.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// Every link in a Tweet is wrapped in a t.co redirect, and Twitter's servers
// record each request to it. The API already sends the real destination next to
// every t.co link, so everything here works offline: links are swapped for
// their destinations before they open, and the background requests the app
// makes to t.co for analytics and safety checks are never sent.

static BOOL BlocksLinkTracking(void) {
    return [BHTSettings boolForKey:@"block_link_tracking"];
}

static BOOL IsTalonURL(NSURL* url) {
    return [url isKindOfClass:[NSURL class]] && [url.host.lowercaseString isEqualToString:@"t.co"];
}

static BOOL IsWebURL(NSURL* url) {
    NSString* scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"];
}

// MARK: - Known t.co destinations

// t.co paths are case-sensitive, so only the scheme is normalised.
static NSString* TalonCacheKey(NSURL* url) {
    return [@"t.co" stringByAppendingString:url.path ?: @""];
}

// Destinations of the t.co links seen so far, for the few places that open a
// link without passing its expansion along.
static NSCache<NSString*, NSURL*>* KnownDestinations(void) {
    static NSCache* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 2000;
    });
    return cache;
}

static void RememberDestination(NSString* talonString, NSString* destinationString) {
    NSURL* talonURL = [NSURL URLWithString:talonString];
    NSURL* destination = [NSURL URLWithString:destinationString];
    if (IsTalonURL(talonURL) && IsWebURL(destination) && !IsTalonURL(destination)) {
        [KnownDestinations() setObject:destination forKey:TalonCacheKey(talonURL)];
    }
}

// MARK: - Tracking parameters

static BOOL IsTrackingParameter(NSString* name, NSString* host) {
    static NSSet<NSString*>* names;
    static NSSet<NSString*>* shareIDHosts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = [NSSet setWithArray:@[
            @"fbclid", @"gclid", @"gclsrc", @"dclid", @"gbraid", @"wbraid", @"msclkid",
            @"twclid", @"ttclid", @"li_fat_id", @"igshid", @"igsh", @"mc_cid", @"mc_eid",
            @"_hsenc", @"_hsmi", @"mkt_tok", @"yclid", @"ref_src"
        ]];
        // si is a per-share tracking ID on these hosts but can mean anything
        // elsewhere.
        shareIDHosts = [NSSet setWithArray:@[
            @"youtube.com", @"m.youtube.com", @"music.youtube.com", @"youtu.be",
            @"open.spotify.com"
        ]];
    });

    NSString* lowercaseName = name.lowercaseString;
    if ([lowercaseName hasPrefix:@"utm_"] || [names containsObject:lowercaseName]) {
        return YES;
    }

    NSString* lowercaseHost = host.lowercaseString;
    if ([lowercaseHost hasPrefix:@"www."]) {
        lowercaseHost = [lowercaseHost substringFromIndex:4];
    }
    return [lowercaseName isEqualToString:@"si"] && [shareIDHosts containsObject:lowercaseHost];
}

static NSURL* URLByStrippingTrackingParameters(NSURL* url) {
    if (!IsWebURL(url)) {
        return url;
    }

    NSURLComponents* components = [NSURLComponents componentsWithURL:url
                                             resolvingAgainstBaseURL:NO];
    // The percent-encoded accessors leave the remaining parameters byte-for-byte
    // as they were.
    NSArray<NSURLQueryItem*>* items = components.percentEncodedQueryItems;
    if (items.count == 0) {
        return url;
    }

    NSMutableArray<NSURLQueryItem*>* keptItems = [NSMutableArray arrayWithCapacity:items.count];
    for (NSURLQueryItem* item in items) {
        if (!IsTrackingParameter(item.name.stringByRemovingPercentEncoding ?: item.name,
                                 components.host)) {
            [keptItems addObject:item];
        }
    }
    if (keptItems.count == items.count) {
        return url;
    }

    components.percentEncodedQueryItems = keptItems.count > 0 ? keptItems : nil;
    return components.URL ?: url;
}

// MARK: - Open links at their destination

// The URL a tapped link should actually open, or the same object when nothing
// needs changing.
static NSURL* DestinationForLink(NSURL* url, NSURL* expandedURL) {
    NSURL* destination = url;

    if (BlocksLinkTracking() && IsTalonURL(url)) {
        if (IsWebURL(expandedURL) && !IsTalonURL(expandedURL)) {
            destination = expandedURL;
        } else {
            destination = [KnownDestinations() objectForKey:TalonCacheKey(url)] ?: url;
        }
    }

    if ([BHTSettings boolForKey:@"strip_tracking_params"]) {
        destination = URLByStrippingTrackingParameters(destination);
    }

    return destination;
}

// Every tapped link (Tweet text, link cards, profile bios) funnels into this one
// builder, which decides between the in-app browser, Safari and
// native navigation. Handing it the destination for both URLs means the t.co
// link never reaches the browser, and native x.com links open in the app.
%hook T1ViewControllerNavigationHelper

+ (id)_t1_handlerForURL:(NSURL*)url
             expandedURL:(NSURL*)expandedURL
                 account:(id)account
           scribeContext:(id)scribeContext
    sourceViewController:(id)sourceViewController
          webviewFactory:(id)webviewFactory {
    if (![url isKindOfClass:[NSURL class]]) {
        return %orig;
    }

    NSURL* destination = DestinationForLink(url, expandedURL);
    if (destination == url) {
        return %orig;
    }

    return %orig(destination, destination, account, scribeContext, sourceViewController,
                     webviewFactory);
}

%end

// Links built from URL entities (the visible text, copied links) use the
// destination too. The entity is also used for URLs that never had a t.co
// wrapper (e.g. share links), where expandedURL is nil.
%hook TFSTwitterEntityURL

- (NSString*)url {
    NSString* url = %orig;
    NSString* expandedURL = self.expandedURL;
    if (!BlocksLinkTracking() || expandedURL == nil) {
        return url;
    }

    RememberDestination(url, expandedURL);
    return expandedURL;
}

%end

// MARK: - Background t.co requests

%hook TNUTalonUtilities

// A HEAD request to the t.co link, sent alongside opening the destination so
// the click is still counted.
+ (BOOL)sendTalonRequestForAnalytics:(NSURL*)url {
    return BlocksLinkTracking() ? NO : %orig;
}

// Requests the t.co link to check it against Twitter's unsafe-link list. The
// completion gets the same result as for a link that isn't a t.co link (0),
// which leaves the in-app browser and app cards to carry on as normal.
+ (id)verifyTalonURL:(NSURL*)url completion:(void (^)(NSInteger result))completion {
    if (!BlocksLinkTracking() || !IsTalonURL(url)) {
        return %orig;
    }

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(0);
        });
    }
    return nil;
}

%end

// MARK: - Click IDs

// Promoted links get a twclid parameter tying the visit back to the click.
%hook T1TwitterClickIDHandler

+ (NSURL*)URLByAppendingTwitterClickIDIfNecessary:(NSURL*)url
                                           status:(id)status
                                          account:(id)account
                                       scribePage:(id)scribePage
                                  scribeComponent:(id)scribeComponent {
    return BlocksLinkTracking() ? url : %orig;
}

%end

%hook T1UnifiedCardBrowserDestinationHandlerHelper

- (NSURL*)urlByAppendingTwitterClickIDToUrl:(NSURL*)url scribeComponent:(id)scribeComponent {
    return BlocksLinkTracking() ? url : %orig;
}

%end

%hook T1UnifiedCardXLinkDestinationHandlerHelper

- (NSURL*)urlByAppendingTwitterClickIDToUrl:(NSURL*)url scribeComponent:(id)scribeComponent {
    return BlocksLinkTracking() ? url : %orig;
}

%end

%hook TUCJobDetailsComponentModel

+ (id)conditionallyApplyPromotedContentClickID:(id)clickID toDestination:(id)destination {
    return BlocksLinkTracking() ? destination : %orig;
}

%end

// Advertiser links can be rerouted through a measurement-partner redirect that
// syncs an ad ID before landing on the destination.
%hook TFNTwitterAdsTPMIdSyncManager

- (BOOL)shouldCreateRedirectURLForURL:(NSURL*)url {
    return BlocksLinkTracking() ? NO : %orig;
}

- (NSURL*)createRedirectURLForURLIfNeeded:(NSURL*)url {
    return BlocksLinkTracking() ? url : %orig;
}

%end
