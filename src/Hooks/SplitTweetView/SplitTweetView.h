#import "../HookHelpers.h"

extern char BHTSplitTweetStateKey;

BOOL BHTSplitTweetViewEnabled(void);
BHTSplitTweetState* BHTTweetState(id object);
BHTSplitTweetState* BHTTweetStateForController(UIViewController* controller);
BOOL BHTIsConversationController(UIViewController* controller);
BOOL BHTRouteTweetToDetail(UINavigationController* primary, UIViewController* controller);
BOOL BHTRouteAppendedTweet(UINavigationController* primary, NSArray<UIViewController*>* controllers);
BHTSplitTweetHostController* BHTMakeTweetColumnHost(UIViewController* content);
void BHTAttachTweetColumn(T1AppSplitViewController* split, BHTSplitTweetHostController* host);
UIView* BHTTweetColumnAppView(BHTSplitTweetHostController* host);
void BHTLayoutTweetColumnChrome(BHTSplitTweetHostController* host);
