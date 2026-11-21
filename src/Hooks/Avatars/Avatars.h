#import "../HookHelpers.h"

static char kCoercedAvatarStyle;
static char kAvatarBarOriginalBackground;
static char kDashAvatarOriginalBorderWidth;

NSHashTable* AvatarBarItems(void);
NSInteger CoercedStyle(UIView* view, NSInteger style);
void UpdateDashAvatarDecorations(UIView* avatar);
void RefreshAvatarBarBackgrounds(void);
void applySquareAvatarsSetting(void);
