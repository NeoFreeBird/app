#import "Ads.h"

%hook TFNTwitterStatus

- (_Bool)isCardHidden {
    return ([BHTSettings boolForKey:@"hide_promoted"] && [self isPromoted])
               ? true
               : %orig;
}

%end

// MARK: - Immersive video feed

// The vertical video feed keeps its own card list and never goes through
// TFNItemsDataViewController, so promoted cards are dropped from that list
// before they become pages.

%hook T1ImmersiveViewController

- (void)viewWillLayoutSubviews {
    RemovePromotedImmersiveCards(self);
    %orig;
}

%end

%hook TNLResponseInfo

- (instancetype)initWithFinalURLRequest:(NSURLRequest*)request
                            URLResponse:(NSURLResponse*)response
                                 source:(NSInteger)source
                                   data:(NSData*)data
                     temporarySavedFile:(id)temporarySavedFile {
    if ([BHTSettings boolForKey:@"hide_promoted"] && data &&
        IsImmersiveTimelineURL(request.URL)) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        BOOL removed = NO;
        id filtered = json ? RemovePromotedEntries(json, &removed) : nil;
        if (removed) {
            data = [NSJSONSerialization dataWithJSONObject:filtered options:0 error:nil]
                       ?: data;
        }
    }

    return %orig(request, response, source, data, temporarySavedFile);
}

%end
