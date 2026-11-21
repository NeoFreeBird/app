#import "../HookHelpers.h"

static char kCoercedAvatarStyle;
static char kAvatarBarOriginalBackground;
static char kDashAvatarOriginalBorderWidth;
static char kFleetBorderOriginalStyle;

NSHashTable* AvatarBarItems(void);
NSInteger CoercedStyle(UIView* view, NSInteger style);
void UpdateDashAvatarDecorations(UIView* avatar);
BOOL UpdateFleetBorderStyle(UIView* view);
void RefreshAvatarBarBackgrounds(void);
void applySquareAvatarsSetting(void);
