//
//  HideUI.x
//  NeoFreeBird
//

#import "HookHelpers.h"

@interface T1ConversationFooterItem : NSObject
@property (nonatomic, retain) NSNumber* viewCount;
@end

// MARK: - Hide Blue verified checkmark

// The author-row badge (SimpleBadgeable.init(statusViewModel:)) builds from the
// merged verified flag plus identityType and ignores isBlueVerified, so both
// getters must be silenced; brand/government badges survive via identityType.
// TFNTwitterUser and TFNTwitterCanonicalUser forward here and need no hooks.

%hook TFSTwitterUser

- (id)isBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? nil : %orig;
}

- (BOOL)verified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

// Reaches into the wrapped user's storage directly instead of through its
// getter.
%hook TFSTwitterUserSource

- (id)isBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? nil : %orig;
}

- (BOOL)verified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

%hook TFSTwitterTypeaheadUser

- (id)isBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? nil : %orig;
}

- (BOOL)verified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

%hook TFSDirectMessageUser

- (id)isBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? nil : %orig;
}

- (BOOL)verified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

// Status view models cache these flags at init, beyond the user model hooks;
// the author row badge reads isFromUserVerified, and other view models forward
// here.
%hook T1TwitterCoreStatusViewModelAdapter

- (BOOL)isFromUserBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

- (BOOL)isFromUserVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

// MARK: - No search history

// Every recent-search write funnels through _tse_setRecentSearch: and every
// read through recentSearches; the separate saved-searches feature stays
// untouched.

%hook TTSRecentSearchesDatastore

- (void)_tse_setRecentSearch:(__unsafe_unretained id)item {
    if (![BHTSettings boolForKey:@"no_history"]) {
        %orig;
    }
}

- (NSArray*)recentSearches {
    return [BHTSettings boolForKey:@"no_history"] ? @[] : %orig;
}

%end

// MARK: - Hide trending content on the Explore tab

// Trending content lives in the child URT chrome view controller, whose
// property has no ObjC getter in 12.3, so find it among the children. The page
// tab strip arrives separately through tfn_navigationBarAccessoryView.

%hook _TtC14T1TwitterSwift28GuideContainerViewController

- (void)viewDidLoad {
    %orig;

    if ([BHTSettings boolForKey:@"hide_trends"]) {
        UIView* viewIfLoaded = [(UIViewController*)self viewIfLoaded];
        if (viewIfLoaded) {
            viewIfLoaded.hidden = YES;
            viewIfLoaded.userInteractionEnabled = NO;
        }
        for (UIViewController* child in
             [(UIViewController*)self childViewControllers]) {
            if ([child isKindOfClass:
                           %c(_TtC14T1TwitterSwift23URTChromeViewController)]) {
                child.view.hidden = YES;
            }
        }
    }
}

- (UIView*)tfn_navigationBarAccessoryView {
    return [BHTSettings boolForKey:@"hide_trends"] ? nil : %orig;
}

%end

%hook UIView
- (void)didMoveToWindow {
    %orig;
    if ([BHTSettings boolForKey:@"hide_trends"] && [self.accessibilityIdentifier isEqualToString:@"T1TwitterSwift.TrendsSidebarViewController"] && is_iPad()) {
        self.hidden = YES;
        self.userInteractionEnabled = NO;
        for (UIView* subview in self.subviews) {
            subview.hidden = YES;
        }
    }
    if ([BHTSettings boolForKey:@"hide_who_to_follow"] && [self.accessibilityIdentifier isEqualToString:@"T1UserRecommendationsViewController"] && is_iPad()) {
        self.hidden = YES;
        self.userInteractionEnabled = NO;
        for (UIView* subview in self.subviews) {
            subview.hidden = YES;
        }
    }
}

%end

// MARK: - No Subscribe button

// Every Subscribe surface — the profile button provider (and its answers that
// demote or hide the Follow button) and the tweet author row — shows only when
// the relationship's eligible state is 1, so reporting "not eligible" (2) is
// enough to keep the plain Follow button everywhere. Relationships that are
// actively super-following stay genuine, so a real subscription keeps its
// Subscribed button and subscriber timeline.

%hook TFSTwitterRelationship

- (NSInteger)superFollowEligibleState {
    if ([BHTSettings boolForKey:@"restore_follow_button"] &&
        self.superFollowingState != 1) {
        return 2;
    }
    return %orig;
}

%end

// MARK: - Hide Follow and Message buttons on Tweets

// The conversation focal tweet and the immersive player both render their
// author row through TTAStatusAuthorView, so applying the settings here covers
// both surfaces.

%hook TTAStatusAuthorView

- (void)setFollowControlHidden:(BOOL)hidden {
    %orig([BHTSettings boolForKey:@"hide_follow_button"] ? YES : hidden);
}

// Both content updates and layout use this setter, so later frame-based
// visibility updates cannot undo the preference. Native visibility is retained
// when the preference is off, including for cached and reused author rows.
- (void)_t1_screenshots_modified_setHidden:(BOOL)hidden view:(UIView*)view {
    if (view && view == self.messageButton &&
        [BHTSettings boolForKey:@"hide_message_button"]) {
        hidden = YES;
        view.userInteractionEnabled = NO;
    }
    %orig(hidden, view);
}

%end

// Hiding views also requires hooking the footer, and X is being weird and making it
// more complicated than it should be.
%hook T1ConversationFooterTextView

- (void)updateFooterTextView {
    if (![BHTSettings boolForKey:@"hide_view_count"]) {
        %orig;
        return;
    }

    T1ConversationFooterItem* footerItem = self.footerItem;
    NSNumber* viewCount = footerItem.viewCount;
    footerItem.viewCount = nil;
    @try {
        %orig;
    } @finally {
        footerItem.viewCount = viewCount;
    }
}

+ (CGSize)sizeForViewModel:(id)model
                          footerItem:(T1ConversationFooterItem*)footerItem
                        maximumWidth:(CGFloat)width
    grokEditImageButtonConfiguration:(id)configuration {
    if (![BHTSettings boolForKey:@"hide_view_count"] || !footerItem) {
        return %orig;
    }

    NSNumber* viewCount = footerItem.viewCount;
    footerItem.viewCount = nil;
    CGSize size;
    @try {
        size = %orig;
    } @finally {
        footerItem.viewCount = viewCount;
    }
    return size;
}

%end

// MARK: - Hide inline action buttons

%hook TTAStatusInlineActionsView

+ (NSArray*)_t1_inlineActionViewClassesForViewModel:(id)arg1
                                            options:(NSUInteger)arg2
                                        displayType:(NSUInteger)arg3
                                            account:(id)arg4 {
    NSArray* origClasses = %orig;
    if (![origClasses isKindOfClass:NSArray.class]) {
        return origClasses;
    }

    NSMutableArray* newClasses = [origClasses mutableCopy];

    Class analyticsButtonClass = %c(TTAStatusInlineAnalyticsButton);
    if (analyticsButtonClass && [BHTSettings boolForKey:@"hide_view_count"]) {
        [newClasses removeObject:analyticsButtonClass];
    }

    Class bookmarkButtonClass = %c(TTAStatusInlineBookmarkButton);
    if (bookmarkButtonClass && [BHTSettings boolForKey:@"hide_bookmark_button"]) {
        [newClasses removeObject:bookmarkButtonClass];
    }

    Class downvoteButtonClass = %c(TTAStatusInlineDownvoteButton);
    if (downvoteButtonClass && [BHTSettings boolForKey:@"hide_downvote_button"]) {
        [newClasses removeObject:downvoteButtonClass];
    }

    return [newClasses copy];
}

%end

%hook T1StandardStatusAskGrokButtonView

- (void)didMoveToWindow {
    %orig;
    if ([BHTSettings boolForKey:@"hide_grok_create"]) {
        self.hidden = YES;
        self.userInteractionEnabled = NO;
        for (UIView* subview in self.subviews) {
            subview.hidden = YES;
        }
        [self.superview setNeedsLayout];
        [self.superview layoutSubviews];
    }
}
%end

%hook XDSButton

- (void)didMoveToWindow {
    %orig;
    if ([self respondsToSelector:@selector(allTargets)]) {
        NSSet* allTargets = [self performSelector:@selector(allTargets)];
        for (id target in allTargets) {
            if ([target isKindOfClass:%c(PaymentsButtonViewModel)]) {
                self.hidden = YES;
                self.userInteractionEnabled = NO;
            }
        }
    }
}

%end

%hook _TtC13QuickComposer21QuickComposerSlotView
- (void)didMoveToWindow {
    %orig;
    if ([BHTSettings boolForKey:@"hide_quick_compose"]) {
        self.hidden = YES;
        self.userInteractionEnabled = NO;
        for (UIView* subview in self.subviews) {
            subview.hidden = YES;
        }
    }
}

%end

%hook T1StatusEditedOnXLabelAdapter

- (BOOL)shouldBeVisibleForViewModel:(id)viewModel {
    return [BHTSettings boolForKey:@"hide_made_on_x"] ? NO : %orig;
}

%end

// MARK: Hide the refresh pill at the top of the page that appears when new tweets are available
%hook TFNPillControl
- (void)didMoveToWindow {
    %orig;

    if ([BHTSettings boolForKey:@"hide_timeline_prompts"]) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

%end

%hook TFNFloatingActionButton
- (void)didMoveToWindow {
    %orig;

    if ([BHTSettings boolForKey:@"hide_tweet_button"]) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

%end

// MARK: - Hide custom timelines

static __weak NSObject* PinnedTimelinesRepository;
static NSArray* LastPinnedTimelineModels;
static BOOL PinnedTimelinesWriteBypass = NO;

// Applies a toggle without relaunching. Hiding rewrites the UNCHANGED pinned
// list purely to republish — updatePinnedTimelines: persists server-side, so
// anything else would unpin for real; the delegate hook below swaps in the
// empty list on the way through.
void applyHideCustomTimelinesSetting(void) {
    NSObject* repository = PinnedTimelinesRepository;
    if (!repository) {
        return;
    }

    if ([BHTSettings boolForKey:@"hide_custom_timelines"]) {
        NSArray* models = LastPinnedTimelineModels;
        if (models.count > 0) {
            PinnedTimelinesWriteBypass = YES;
            ((void (*)(id, SEL, id))objc_msgSend)(repository, @selector(updatePinnedTimelines:), models);
            PinnedTimelinesWriteBypass = NO;
        }
    } else if ([repository respondsToSelector:@selector(fetchPinnedTimelinesWithThrottleEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            repository, @selector(fetchPinnedTimelinesWithThrottleEnabled:), NO);
    }
}

// The trailing accessory is only reconfigured while the strip is showing, so a
// button built before hiding mid-session survives; sync its visibility here. The
// property is a Swift lazy var whose storage ivar KVC can't see, hence the fallback.
static void SyncHomeAddTabButton(id container, BOOL hidden) {
    UIView* button = nil;

    @try {
        button = [container valueForKey:@"addTabButton"];
    } @catch (__unused NSException* exception) {
        unsigned int ivarCount = 0;
        Ivar* ivars = class_copyIvarList([container class], &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char* name = ivar_getName(ivars[i]);
            if (name && strstr(name, "addTabButton")) {
                button = object_getIvar(container, ivars[i]);
                break;
            }
        }
        free(ivars);
    }

    if ([button isKindOfClass:[UIView class]]) {
        button.hidden = hidden;
    }
}

// The repository publishes the pinned list through this single delegate call, so
// handing it an empty array hides the tabs without touching persisted state.
%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController

- (void)pinnedTimelinesRepository:(id)repository
    didChangeWithPinnedTimelineModels:(NSArray*)models {
    PinnedTimelinesRepository = repository;
    if (models.count > 0) {
        LastPinnedTimelineModels = [models copy];
    }
    BOOL hide = [BHTSettings boolForKey:@"hide_custom_timelines"];

    %orig(repository, hide ? @[] : models);
    SyncHomeAddTabButton(self, hide);
}

- (id)tfn_navigationBarAccessoryView {
    id accessoryView = %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
    return accessoryView;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
    attachNeoFreeBirdSettingsGesture((UIViewController*)self);
}

%end

// While hiding, the overridden pinned-tabs feature switches make the app compute
// an empty pinned list; freeze writes so it can't overwrite the real tabs.
%hook _TtC32TwitterHomeFeatureImplementation31CachedPinnedTimelinesRepository

- (void)updatePinnedTimelines:(id)timelines {
    if (!PinnedTimelinesWriteBypass && [BHTSettings boolForKey:@"hide_custom_timelines"]) {
        return;
    }

    %orig;
}

%end

// MARK: - Hide the Spaces bar

// The bar is still the repurposed Fleets line; both home timeline implementations
// share this visibility gate, re-evaluated on every content or settings update.
%hook T1FleetLineHeaderController

- (BOOL)_t1_shouldShowFleetLine {
    if ([BHTSettings boolForKey:@"hide_spaces"]) {
        return NO;
    }

    return %orig;
}

%end

%hook _TtC14T1TwitterSwift28FleetLineAccessoryController

- (BOOL)isHidden {
    return [BHTSettings boolForKey:@"hide_spaces"] ? YES : %orig;
}

- (UIView*)accessoryView {
    return [BHTSettings boolForKey:@"hide_spaces"] ? nil : %orig;
}

%end