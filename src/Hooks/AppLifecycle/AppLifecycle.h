#import "../HookHelpers.h"

static AuthViewController* padlockController = nil;
static BOOL padlockAuthenticated = NO;
static BOOL testAlertScheduled = NO;
static NSString* const testAlertVersionKey = @"nfb_test_alert_last_seen_version";

extern BOOL padlockAuthenticated;
extern AuthViewController* padlockController;
UIWindow* activeKeyWindow(void);
void showPadlockOverlay(void);
void removePadlockOverlay(void);
NSString* testAlertVersion(void);
void scheduleTestAlertIfNeeded(void);
void stripLaunchRevealMask(UIView* view);
