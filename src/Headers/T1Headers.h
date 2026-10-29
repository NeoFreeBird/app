//
//  T1Headers.h
//  NeoFreeBird
//
//  Created by BandarHelal
//

#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "TFNHeaders.h"
#import "TFSHeaders.h"

@interface TFNTwitterAccountModel : NSObject
- (void)lookUpStatusForID:(long long)statusID completionBlock:(void (^)(id status))completion;
@end

@interface TFNTwitterAccount (PostInteractions)
@property (readonly, nonatomic) TFNTwitterAccountModel* model;
@end

@interface TFNTwitterStatus (PostInteractions)
@property (readonly, nonatomic) long long quoteCount;
@property (readonly, nonatomic) long long retweetCount;
@end

@interface T1PostInteractionsViewController : UIViewController
+ (id)viewControllerWithAccount:(TFNTwitterAccount*)account
                       statusID:(long long)statusID
                   statusUserID:(long long)statusUserID
                     initialTab:(long long)initialTab;
@end

@interface T1AppDelegate : UIResponder <UIApplicationDelegate>
@property (retain, nonatomic) UIWindow* window;
@end

// The "new posts" pill shown at the top of the timeline
@interface TUIUpdateIndicator : UIViewController
@property (nonatomic, strong) TFNPillControl* pillControl;
@end

@interface TUIFollowControlCustomScreenshot : UIView
@end

// Follow/block control on profiles and user rows. Each destructive action is
// split in two: -_blockUser:event: puts up the confirmation and -_doBlockUser:
// event: is what its confirm button ends up calling.
@interface TUIFollowControl : UIView
@property (nonatomic) BOOL confirmBlock;
- (void)_doBlockUser:(id)user event:(id)event;
- (void)_doUnblockUser:(id)user event:(id)event;
- (void)_doBlockMessageUser:(id)user event:(id)event;
- (void)_doUnblockMessageUser:(id)user event:(id)event;
@end

@interface TUIFollowButtonV2 : UIControl
@property (nonatomic) BOOL confirmBlock;
- (void)buttonTapped;
@end

@interface TTMAssetVideoFile : NSObject
@property (nonatomic, copy, readonly) NSString* filePath;
@property (nonatomic, assign, readonly) CGFloat duration;

@end

@interface TTMAssetVoiceRecording : TTMAssetVideoFile
@property (nonatomic, strong, readwrite) NSNumber* totalDurationMillis;
@end

@interface T1MediaAttachmentsViewCell : UICollectionViewCell
@property (nonatomic, strong, readwrite) id attachment;
@property (nonatomic, strong) UIButton* uploadButton;
@end

@interface T1StandardStatusAskGrokButtonView : UIView
@end

@interface T1MediaAttachmentsViewCell () <UINavigationControllerDelegate,
                                          UIImagePickerControllerDelegate>
@end

@interface T1StandardStatusAttachmentViewAdapter : NSObject
@property (nonatomic, assign, readonly) NSUInteger attachmentType;
@end

#pragma mark - Tab bar

@interface T1PanelIdentity : NSObject
+ (NSString*)iconImageNameForPanelID:(long long)panelID;
@end

@interface T1TabView : UIView
@property (readonly, nonatomic) long long panelID;
@property (copy, nonatomic) NSString* scribePage;
@property (readonly, nonatomic) NSString* title;
@property (readonly, nonatomic) NSString* imageName;
@property (readonly, nonatomic) UIImageView* imageView;
@property (readonly, nonatomic) UIView* transformContainer;
@property (retain, nonatomic) UIColor* iconColor;
@property (readonly, nonatomic, getter=isSelected) BOOL selected;
- (void)_t1_updateImageViewAnimated:(BOOL)animated;
- (void)applyTintColor:(UIColor*)color;
@end

@interface T1TabBarViewController : UIViewController
@property (copy, nonatomic) NSArray* tabViews;
@end

// Each entry backs one tab and owns its T1TabView; the app orders both the tab
// buttons and their content view controllers from this single array.
@protocol T1AppNavigationTabEntry <NSObject>
- (T1TabView*)tabView;
@end

@interface T1TabbedAppNavigationViewController : UIViewController
- (void)setVisibleTabEntries:(NSArray<id<T1AppNavigationTabEntry>>*)entries;
// Recomputes the visible tab set at runtime (rebuilds buttons and content).
- (void)recalculateVisiblePanels;
@end

#pragma mark - Settings

// T1GenericSettingsViewController backs the 12.3 "settings revamp" root and its
// sub-pages; T1SettingsViewController is the legacy fallback root.
@interface T1GenericSettingsViewController : TFNItemsDataViewController
@property (nonatomic, strong) TFNTwitterAccount* account;
@end

@interface T1SettingsViewController : TFNItemsDataViewController
@property (nonatomic, strong) TFNTwitterAccount* account;
@end

#pragma mark - Profile

@interface T1ProfileUserViewModel : NSObject
@property (readonly, copy, nonatomic) NSString* location;
@property (readonly, copy, nonatomic) NSString* fullName;
@property (readonly, copy, nonatomic) NSString* username;
@property (readonly, copy, nonatomic) NSString* bio;
@property (readonly, copy, nonatomic) NSString* url;
@property (readonly, copy, nonatomic) TFNTwitterUserDataSource* userDataSource;
@property (readonly, nonatomic) NSNumber* tweetCount;
@end

@interface T1ProfileHeaderViewController : UIViewController
@property (retain, nonatomic) T1ProfileUserViewModel* viewModel;
// Base TFNActionItems for the profile's "More actions" menu, which the Swift
// action button layer asks its host for before presenting.
- (id)profileMoreActionsBaseActionItemsWithSender:(id)sender;
@end

// Hooked for unrounded tweet/post count
@interface T1ProfileDisplayNormalMainContentProvider : NSObject
@property (retain, nonatomic) T1ProfileUserViewModel* viewModel;
- (id)_tweetsSubtitle;
@end

#pragma mark - Status views

@protocol T1StatusInlineActionButtonDelegate <NSObject>
@end
@protocol TTAStatusInlineActionButtonDelegate <NSObject>
@end

@interface TTAStatusInlineShareButton : UIView
@property (nonatomic) __weak id<T1StatusInlineActionButtonDelegate> delegate;
@end

@interface TTAStatusAuthorView : UIView
@property UIButton* messageButton;
@end

@interface TTAStatusInlineReplyButton : UIView
@property (nonatomic) __weak id<T1StatusInlineActionButtonDelegate> delegate;
@end

@interface T1PersistentComposeViewController : UIViewController
@property (readonly, nonatomic) id statusViewModel;
- (void)_t1_sendReply;
@end

@interface T1ImmersiveFullScreenViewController : UIViewController
@property (retain, nonatomic) UIPanGestureRecognizer* dismissGesture;
@end

@interface T1ImmersiveViewController : UIViewController
@end

@interface T1ImmersiveViewControllerV2 : UIViewController
@end

@interface T1URTTimelineStatusItemViewModel : NSObject
@property (nonatomic, readonly) BOOL isRetweet;
@property (nonatomic, readonly) TFNTwitterUser* representedFromUser;
@end

@protocol TTACoreStatusViewEventHandler <NSObject>
@end

@interface T1StatusCell : UITableViewCell <TTACoreStatusViewEventHandler>
@end

@interface T1StatusInlineActionsView
    : UIView <T1StatusInlineActionButtonDelegate>
@property (readonly, nonatomic) id viewModel;
@property (nonatomic) id delegate;
@end

@interface TTAStatusInlineActionsView
    : UIView <TTAStatusInlineActionButtonDelegate>
@property (readonly, nonatomic) id viewModel;
@property (nonatomic) id delegate;
@end

@interface T1StandardStatusView : UIView
@property (nonatomic) __weak id<TTACoreStatusViewEventHandler> eventHandler;
@property (readonly, nonatomic) UIView* visibleInlineActionsView;
@end

@interface T1TweetDetailsFocalStatusView : UIView
@property (nonatomic) __weak id<TTACoreStatusViewEventHandler> eventHandler;
@end

@interface T1ConversationFocalStatusView : UIView
@property (nonatomic) __weak id<TTACoreStatusViewEventHandler> eventHandler;
- (void)layoutSubviews;
@property (nonatomic, readonly) id viewModel;
- (void)enumerateSubviewsRecursively:(void (^)(UIView*))block;
@end

@interface T1TweetComposeViewController : UIViewController
@end

#pragma mark - Media views

@class DownloadInlineButton;

// DM media message container (DMConversation.MessageAttachmentView)
@interface _TtC14DMConversation21MessageAttachmentView : UIView
@property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
@property (nonatomic, strong) DownloadInlineButton* downloadHandler;
@end

@interface _TtC14DMConversation21MessageAttachmentView () <
    UIContextMenuInteractionDelegate>
@end

// Shared media view (TweetMediaAttachments.MultiMediaView); its carousel
// variant exposes -inlineMediaInfos as well
@interface _TtC21TweetMediaAttachments14MultiMediaView : UIView
@property (nonatomic, readonly) NSArray* inlineMediaInfos;
@end

@interface _TtC6ChatUI26MessageAttachmentAudioView : UIView
@end

#pragma mark - Host & web views

@interface T1HostViewController : UIViewController
+ (instancetype)sharedHostViewController;
- (id)currentAccount;
@end

@interface T1BaseWebViewController : UIViewController
- (instancetype)initWithURL:(NSURL*)url;
- (instancetype)initWithAccount:(id)account;
- (void)setRootURL:(NSURL*)url;
- (void)setCurrentURL:(NSURL*)url;
@property (nonatomic, readonly) NSURL* currentURL;
- (WKWebView*)webView;
@end

@interface T1WebViewController : T1BaseWebViewController
- (instancetype)initWithRootURL:(NSURL*)rootURL
                        account:(id)account
             shouldAuthenticate:(BOOL)shouldAuthenticate
      shouldPresentAsNativePage:(BOOL)shouldPresentAsNativePage
                   sourceStatus:(id)sourceStatus
                scribeComponent:(id)scribeComponent
               scribeParameters:(id)scribeParameters;
@property (nonatomic, strong) id account;
- (BOOL)doesURLResultTypeOpenInWebview:(long long)resultType;
@end

@interface T1SafariViewController : SFSafariViewController
@property (nonatomic, readonly) NSURL* rootURL;
@end

#pragma mark - Status & timeline text

@interface T1StatusBodyTextView : UIView
@property (readonly, nonatomic) id viewModel;
@end

@interface _TtC10TwitterURT25URTTimelineTrendViewModel : NSObject
@property (nonatomic, readonly) NSDictionary* scribeItem;
@end

@interface _TtC14T1TwitterSwift24ImmersivePiPDropZoneView : UIView
@end

@interface _TtC14T1TwitterSwift17VideoControlsView : UIView
@end

@class T1ConversationFooterItem;

@interface T1ConversationFooterTextView : TFNAttributedTextView
@property (nonatomic, retain) T1ConversationFooterItem* footerItem;
@property (nonatomic, readonly) id viewModel;
- (void)updateFooterTextView;
+ (CGSize)sizeForViewModel:(id)model
                          footerItem:(T1ConversationFooterItem*)item
                        maximumWidth:(CGFloat)width
    grokEditImageButtonConfiguration:(id)configuration;
@end

@interface T1VideoQualityUploadSettings : NSObject
- (_Bool)shouldAllowFullHdVideoUpload:(long long)upload;
@end
// Hooked for unrounded follower/following counts
@interface T1ProfileFriendsFollowingViewModel : NSObject
- (id)_t1_followCountTextWithLabel:(id)arg1
                     singularLabel:(id)arg2
                             count:(id)arg3
                       highlighted:(_Bool)arg4;
@end

@interface T1AnimatedLaunchScreenView : UIView
- (void)layoutSubviews;
- (void)traitCollectionDidChange:(id)change;
@end

@interface T1PollingResultsView : UIView
@property (nonatomic) double percentage;
@property (retain, nonatomic) NSString* percentageString;
@property (nonatomic) _Bool hasVoted;
@end

@interface T1PollingCardView : UIView
- (id)initWithFrame:(CGRect)frame;
@property (retain, nonatomic) NSArray* choiceButtons;
@property (retain, nonatomic) NSArray* resultViews;
@property (retain, nonatomic) TFNTappableHighlightView* pollChoiceContainer;
@property (retain, nonatomic) TFNTappableHighlightView* pollResultContainer;
@property (retain, nonatomic) TFNTappableHighlightView* pollStatusContainer;
@end

@interface TFCCardData : NSObject
@property (readonly, copy, nonatomic) NSString* name;
- (NSString*)stringForKey:(NSString*)key;
- (NSString*)stringForKey:(NSString*)key defaultValue:(NSString*)value;
- (NSNumber*)numberForKey:(NSString*)key;
- (NSNumber*)numberFromStringForKey:(NSString*)key;
- (BOOL)boolForKey:(NSString*)key;
@end

@interface TAVPlaybackState : NSObject
// AVPlayer semantics: 0 = paused, 1 = waiting to play, 2 = playing
@property (nonatomic, readonly) long long timeControlStatus;
@end

@interface TAVPlayer : NSObject
@property (nonatomic, readonly) TAVPlaybackState* playbackState;
- (void)play;
- (void)pause;
- (void)playOrReplay;
@end

@interface _TtC14T1TwitterSwift22ImmersiveVideoPageView : UIView
@end

@interface _TtC14T1TwitterSwift17ImmersiveCardView : UIView
- (void)setPausedByUser:(BOOL)paused;
@end

@interface _TtC16ChatConversation24ScreenshotProtectionView : UIView
@end

@interface T1AppSplitSideBarViewController : UIViewController
@end

@interface T1ViewControllerScribeEventObserver : NSObject
- (void)viewControllerApplicationDidBecomeActive:(id)active;
@end

@interface T1TabCustomizationConfig : NSObject
@property (nonatomic, readonly) _Bool isTabCustomizationEnabled;
@end

@interface T1BlockMuteActionPerformer : NSObject
- (void)showBlockAlertForContext:(id)context;
@end

@interface _TtC14T1TwitterSwift28FleetLineAccessoryController : NSObject
@end

@interface T1AppSplitViewController : UIViewController
@property (nonatomic, readonly) UIViewController* extendedContentViewController;
@property (nonatomic, weak) id delegate;
@property (nonatomic) BOOL displaySideBar;
- (void)setDisplayExtendedContent:(BOOL)display animated:(BOOL)animated;
- (NSInteger)private_splitModeForSize:(CGSize)size
               displayExtendedContent:(BOOL)display
                       displaySideBar:(BOOL)sideBar;
@end

@interface T1ExtendedContentNavigationController : TFNNavigationController
@end

@interface T1TabNavigationController : TFNNavigationController
@end

@interface PaymentsButtonViewModel : NSObject
@end

@interface T1StatusEditedOnXLabelAdapter: NSObject
- (_Bool)shouldBeVisibleForViewModel:(id)model;
@end
