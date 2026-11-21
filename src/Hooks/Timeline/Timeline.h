#import "../HookHelpers.h"

static const void* EditHistoryViewControllerKey = &EditHistoryViewControllerKey;
static const void* ConversationOpenedFromProfileKey = &ConversationOpenedFromProfileKey;
// Twitter's *ByCurrentAccountState fields are a tri-state (0 unknown, 1 yes,
// 2 no); if follows still get hidden, flip this to the value logged for a
// known-followed account.
static const NSInteger kFollowedByCurrentAccountStateFollowing = 1;
static const NSInteger kBlockingCurrentAccountStateBlocking = 1;

BOOL IsGraphQLResponse(NSURL* url);
id RemoveVideoCarouselEntries(id node, BOOL* removed);
BOOL IsInHierarchyOfClass(UIViewController* viewController, NSString* className);
BOOL IsInEditHistory(UIViewController* viewController);
BOOL NavigationMetadataIsFromProfile(id metadata);
BOOL IsInProfileOriginConversation(UIViewController* viewController);
long long ConversationRootUserID(NSArray* sections);
NSSet<NSNumber*>* ConversationAuthorRepliedToUserIDs(NSArray* sections,
                                                     long long rootUserID);
NSArray* FilteredTimelineSections(TFNItemsDataViewController* dataViewController,
                                  NSArray* sections);
