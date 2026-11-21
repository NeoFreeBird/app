#import "TFNHeaders.h"

// Everything the per-item filters need to know about one section update: which
// hide toggles are on, which screen the timeline is being shown on, and the
// conversation lookups those two imply. Adding a filter or a surface means
// adding a property here, a line in +contextForDataViewController: and a line
// in -isEqualToContext:, instead of another argument threaded through every
// function in this section.
@interface BHTimelineFilterContext : NSObject

// Hide toggles, already resolved against the surface — hideVerified stays off
// in profiles and search, where seeing the account that was looked up is the
// whole point of being there.
@property (nonatomic) BOOL hideWhoToFollow;
@property (nonatomic) BOOL hidePrompts;
@property (nonatomic) BOOL hideVerified;
@property (nonatomic) BOOL hideQuoteTweets;
@property (nonatomic) BOOL hideRetweets;
@property (nonatomic) BOOL hideBlockedRetweets;

// Surfaces.
@property (nonatomic) BOOL inConversation;
@property (nonatomic) BOOL inProfile;
@property (nonatomic) BOOL openedFromProfile;
@property (nonatomic) BOOL inSearch;
@property (nonatomic) BOOL inEditHistory;
@property (nonatomic) BOOL inNotifications;

// Conversation lookups, filled in by -resolveConversationLookupsInSections:
// once per section update and only when hiding verified replies needs them.
@property (nonatomic) long long conversationRootUserID;
@property (nonatomic, copy) NSSet<NSNumber*>* authorRepliedToUserIDs;

// NO when nothing in this context can hide anything, so the sections can be
// handed back untouched.
@property (nonatomic, readonly) BOOL shouldFilter;

+ (instancetype)contextForDataViewController:(TFNItemsDataViewController*)dataViewController;
- (void)resolveConversationLookupsInSections:(NSArray*)sections;
- (BOOL)isEqualToContext:(BHTimelineFilterContext*)other;

@end

@interface NFBSettingsGesture : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController* home;
@end

@interface BHTTenorURLProtocol : NSURLProtocol
@end

@interface BHTSplitTweetHostController : UIViewController
@property (nonatomic, strong) UIViewController* content;
@property (nonatomic, strong) UINavigationController* detail;
@property (nonatomic, strong) UIView* divider;
@property (nonatomic) BOOL detailVisible;
@property (nonatomic) BOOL appeared;
@property (nonatomic, strong) UIViewPropertyAnimator* columnAnimator;
- (instancetype)initWithContent:(UIViewController*)content detail:(UINavigationController*)detail;
- (BOOL)hasRoomForDetail;
- (void)finishColumnAnimation;
- (void)setDetailVisible:(BOOL)visible animated:(BOOL)animated completion:(void (^)(void))completion;
@end

@interface BHTSplitTweetState : NSObject
@property (nonatomic, weak) T1AppSplitViewController* split;
@property (nonatomic, weak) BHTSplitTweetHostController* glassHost;
@property (nonatomic, weak) UINavigationController* detail;
@property (nonatomic, weak) UINavigationController* primary;
@property (nonatomic, weak) UIViewController* primaryScreen;
@property (nonatomic, weak) UIViewController* conversation;
@property (nonatomic, strong) UIViewController* emptyController;
@property (nonatomic, copy) NSArray<UIBarButtonItem*>* originalLeftItems;
@property (nonatomic, strong) UIBarButtonItem* closeItem;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL collapsed;
@property (nonatomic) BOOL updating;
@property (nonatomic) BOOL updateScheduled;
@property (nonatomic) BOOL waitingForTransition;
@property (nonatomic) BOOL nativeColumnTransitioning;
- (BOOL)showConversation:(UIViewController*)controller
             fromPrimary:(UINavigationController*)primary;
- (void)scheduleUpdate;
- (void)discardHiddenDetail;
@end

@class HFSensitiveTweetBlurredInterstitialView;

@protocol BHTSensitiveMediaOverlayDelegate <NSObject>
- (BOOL)blurViewRequiresAgeVerificationToRevealWithBlurView:(HFSensitiveTweetBlurredInterstitialView*)view;
@end

@interface HFSensitiveTweetBlurredInterstitialView : UIView
@property (nonatomic, readonly) BOOL blurViewIsHidden;
@property (nonatomic, readonly) id<BHTSensitiveMediaOverlayDelegate> delegate;
- (void)showOrHideMediaButtonPressed:(id)sender;
@end

@interface BHTPostInteractionTitleLabel : UILabel
@end
