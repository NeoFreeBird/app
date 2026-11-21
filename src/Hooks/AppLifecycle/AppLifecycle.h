#import "../HookHelpers.h"

static NSString* const testAlertVersionKey = @"nfb_test_alert_last_seen_version";
static BOOL testAlertScheduled = NO;
static BOOL padlockAuthenticated = NO;
static AuthViewController* padlockController = nil;
UIWindow* activeKeyWindow(void);
void showPadlockOverlay(void);
void removePadlockOverlay(void);
NSString* testAlertVersion(void);
void scheduleTestAlertIfNeeded(void);
void stripLaunchRevealMask(UIView* view);
