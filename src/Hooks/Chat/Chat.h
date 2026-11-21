#import <string.h>
#import "../HookHelpers.h"

static NSInteger nfb_secureEntrySuppression = 0;
static void* NFBNeutralizedCanvasKey = &NFBNeutralizedCanvasKey;

BOOL shouldDropScreenshotProtection(UIView* protectionView);
void applyChatScreenTint(UIView* view);
void disableSecureCanvas(UIView* protectionView);
