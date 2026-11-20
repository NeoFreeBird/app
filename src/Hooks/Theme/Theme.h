#import <UIKit/UIKit.h>
#import "BHTDimPalette.h"

@class T1TabView, XDSBlur;
@protocol TAEColorPalette;

void applySelectedThemeColor(void);
void BHTApplyDimToVideoControls(UIView* controlsView);

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
NSArray* BHTDimScrollEdgeColors(NSArray* colors, UITraitCollection* traits);
void BHTApplyScrollEdgeBlur(XDSBlur* blur);
void BHTApplyScrollEdgeFade(UIView* fade);
void BHTApplyDimScrollEdgeChildren(UIView* treatment);
UIColor* BHTDimNormalizedViewBackground(UIView* view, UIColor* color);
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
