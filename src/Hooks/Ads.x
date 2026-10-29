//
//  Ads.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// Timeline items are removed from the section data before it reaches the data
// view controller, so no empty cells or gaps are left behind. This covers every
// timeline surface (home, profile, search, conversations) regardless of whether
// it renders through a table view or the newer diffable collection view path.

static BOOL StatusItemIsPromoted(id item) {
    SEL isPromoted = @selector(isPromoted);
    if ([item respondsToSelector:isPromoted] && [item isPromoted]) {
        return YES;
    }

    Ivar statusIvar = class_getInstanceVariable([item class], "status");
    if (!statusIvar) {
        return NO;
    }

    TFNTwitterStatus* status = object_getIvar(item, statusIvar);
    return [status respondsToSelector:@selector(isPromoted)] && status.isPromoted;
}

// Promoted trends and event summary heroes (the image ads at the top of
// explore) carry their promotion in the Swift-side `promotedContent` stored
// property, which isn't always reflected in the scribe item.
static BOOL ItemHasPromotedContent(id item) {
    Ivar promotedIvar =
        class_getInstanceVariable([item class], "promotedContent");
    return promotedIvar && object_getIvar(item, promotedIvar) != nil;
}

static BOOL ScribeItemIsPromoted(id item) {
    if (![item respondsToSelector:@selector(scribeItem)]) {
        return NO;
    }

    NSDictionary* scribeItem = [item performSelector:@selector(scribeItem)];
    return [scribeItem isKindOfClass:[NSDictionary class]] &&
           scribeItem[@"promoted_id"] != nil;
}

static BOOL ShouldHideItem(id item, NSString* location) {
    item = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([item classForCoder]);

    if ([BHTSettings boolForKey:@"hide_promoted"]) {
        // Treat the model's promotion flag as authoritative. The concrete
        // status-item class has changed across app versions, so don't gate
        // this check on a runtime class name.
        if (StatusItemIsPromoted(item)) {
            return YES;
        }

        BOOL isExplorePromotion =
            [className isEqualToString:@"TwitterURT.URTTimelineTrendViewModel"] ||
            [className
                isEqualToString:@"TwitterURT.URTTimelineEventSummaryViewModel"];
        if (isExplorePromotion &&
            (ScribeItemIsPromoted(item) || ItemHasPromotedContent(item))) {
            return YES;
        }

        if ([className
                isEqualToString:@"TwitterURT.URTTimelineGoogleNativeAdViewModel"]) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_premium_offer"]) {
        if ([className
                isEqualToString:@"TwitterURT.URTTimelineMessageItemViewModel"]) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_trend_videos"] &&
        [location isEqualToString:@"OTHER"]) {
        if ([className
                isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
            return YES;
        }
    }

    return NO;
}

static NSArray* FilteredSections(TFNItemsDataViewController* dataViewController,
                                 NSArray* sections) {
    if (!([BHTSettings boolForKey:@"hide_promoted"] ||
          [BHTSettings boolForKey:@"hide_premium_offer"] ||
          [BHTSettings boolForKey:@"hide_trend_videos"])) {
        return sections;
    }

    NSString* location =
        [dataViewController respondsToSelector:@selector(adDisplayLocation)]
            ? dataViewController.adDisplayLocation
            : nil;

    BOOL modified = NO;
    NSMutableArray* filteredSections =
        [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSUInteger count = items.count;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < count; i++) {
            if (ShouldHideItem(items[i], location)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        modified = YES;

        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? filteredSections : sections;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections
    restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig(FilteredSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredSections(self, sections), identifiers, animation,
              completion);
}

%end

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

static BOOL ImmersiveCardIsPromoted(id card) {
    if ([card isKindOfClass:objc_getClass("_TtC14T1TwitterSwift36ImmersiveGoogleNativeAdCardViewModel")]) {
        return YES;
    }

    Ivar itemIvar =
        class_getInstanceVariable([card class], "statusItemViewModel");
    return itemIvar && StatusItemIsPromoted(object_getIvar(card, itemIvar));
}

// The coordinator's `items` is a Swift [ImmersiveCardViewModelProtocol]. Its
// buffer has the count at +16 and the elements from +32, two words each: the
// card and its protocol witness table.
static void RemovePromotedImmersiveCards(id viewController) {
    if (!viewController || ![BHTSettings boolForKey:@"hide_promoted"]) {
        return;
    }

    Ivar coordinatorIvar =
        class_getInstanceVariable([viewController class], "timelineCoordinator");
    id coordinator =
        coordinatorIvar ? object_getIvar(viewController, coordinatorIvar) : nil;
    Ivar itemsIvar = class_getInstanceVariable([coordinator class], "items");
    if (!itemsIvar) {
        return;
    }

    uint8_t* buffer = *(uint8_t**)((uint8_t*)(__bridge void*)coordinator +
                                   ivar_getOffset(itemsIvar));
    int64_t* count = (int64_t*)(buffer + 16);
    void** elements = (void**)(buffer + 32);

    int64_t first = 0;
    while (first < *count &&
           !ImmersiveCardIsPromoted((__bridge id)elements[first * 2])) {
        first++;
    }
    if (first == *count) {
        return;
    }

    static bool (*isUniquelyReferenced)(const void*);
    static void (*unknownObjectRelease)(void*);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        isUniquelyReferenced =
            dlsym(RTLD_DEFAULT, "swift_isUniquelyReferenced_nonNull_native");
        unknownObjectRelease = dlsym(RTLD_DEFAULT, "swift_unknownObjectRelease");
    });

    // Editing a buffer that another array still shares would change that
    // array too.
    if (!isUniquelyReferenced || !unknownObjectRelease ||
        !isUniquelyReferenced(buffer)) {
        return;
    }

    int64_t kept = first;
    for (int64_t i = first; i < *count; i++) {
        void* card = elements[i * 2];
        if (ImmersiveCardIsPromoted((__bridge id)card)) {
            unknownObjectRelease(card);
            continue;
        }

        elements[kept * 2] = card;
        elements[kept * 2 + 1] = elements[i * 2 + 1];
        kept++;
    }
    *count = kept;
}

%hook T1ImmersiveViewController

- (void)viewWillLayoutSubviews {
    RemovePromotedImmersiveCards(self);
    %orig;
}

%end

static BOOL IsImmersiveTimelineURL(NSURL* url) {
    NSArray* parts = url.path.pathComponents;
    return [parts containsObject:@"graphql"] &&
           [@[@"ImmersiveViewerExploreMixerTimeline", @"ImmersiveProfileViewer"]
               containsObject:parts.lastObject];
}

static id RemovePromotedEntries(id node, BOOL* removed) {
    if ([node isKindOfClass:[NSArray class]]) {
        NSMutableArray* kept = [NSMutableArray array];
        for (id value in node) {
            id entryID = [value isKindOfClass:[NSDictionary class]]
                             ? value[@"entry_id"]
                             : nil;
            if ([entryID isKindOfClass:[NSString class]] &&
                [entryID hasPrefix:@"promoted-tweet-"]) {
                *removed = YES;
                continue;
            }

            [kept addObject:RemovePromotedEntries(value, removed)];
        }
        return kept;
    }

    if ([node isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary* copy = [node mutableCopy];
        for (NSString* key in node) {
            copy[key] = RemovePromotedEntries(node[key], removed);
        }
        return copy;
    }

    return node;
}

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
