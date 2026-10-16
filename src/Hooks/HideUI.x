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
    
-(void)didMoveToWindow {
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
