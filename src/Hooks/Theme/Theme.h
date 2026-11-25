#import <UIKit/UIKit.h>
#import "../HookHelpers.h"
#import "BHTDimPalette.h"

@class T1TabView, XDSBlur, _TtC10TFNUISwift25LegacySegmentedTabBarView;
@protocol TAEColorPalette;

static BOOL updatingTabIconColor = NO;

void applySelectedThemeColor(void);

// Applies or removes Dim without a restart when the setting changes
void BHTDimSettingDidChange(BOOL enabled);
void BHTScheduleDimRefresh(void);

NSNumber* BHTSelectedThemeColor(void);
NSInteger BHTNativeThemeOption(NSInteger option);
UIColor* BHTThemePrimaryColor(id palette, UIColor* native);
UIColor* BHTThemeLoadedColor(id loader, NSString* name, UIColor* color);
UIColor* BHTThemeDynamicColor(UIColor* color, UIColor* resolved);
id<TAEColorPalette> BHTThemeColorPalette(id info, id<TAEColorPalette> realPalette, BOOL isDark);
UIColor* BHTThemeSystemBackground(UIColor* original, UIColor* dim);
UIColor* BHTThemeResolvedBackground(UIColor* original, UITraitCollection* traits);
void BHTUpdateDimGlass(UIView* glass);
BOOL BHTIsInsideScrollEdgeTreatment(UIView* view);
NSArray* BHTThemeGradientColors(CAGradientLayer* layer, NSArray* colors);
void BHTApplyScrollEdgeBlur(XDSBlur* blur);
void BHTApplyScrollEdgeFade(UIView* fade);
void BHTApplyDimScrollEdgeChildren(UIView* treatment);
UIColor* BHTThemeViewBackground(UIView* view, UIColor* color);
void BHTRefreshDimBackground(UIView* view);
void BHTApplyDimSolidColorView(UIView* view);
void BHTApplyDimBarBackground(UIView* bar);
void BHTApplyDisabledBarButtonTextColor(UIViewController* controller);
void BHTRefreshSegmentedTabBarColors(_TtC10TFNUISwift25LegacySegmentedTabBarView* tabBar);
void BHTApplyDimSearchPill(UISearchBar* searchBar);
UIImage* BHTDimSearchPillImage(void);
BOOL BHTIsExploreSearchBackgroundView(UIView* view);
void BHTApplyGlassTabLabels(UIView* bar);
void BHTApplyGlassTabAccent(UIView* item);
void BHTLayoutGlassTabItem(UIView* item);
UIView* BHTPrepareLegacyTabLayout(T1TabView* tabView);
void BHTFinishLegacyTabLayout(T1TabView* tabView, UIView* glyph);
void BHTUpdateLegacyTabLabelColor(T1TabView* tabView, BOOL selected);
void BHTApplySidebarIconTheme(UIViewController* sidebar);
UIColor* BHTTabItemColor(BOOL selected);
BOOL BHTIsGlassIcon(UIImageView* icon);
