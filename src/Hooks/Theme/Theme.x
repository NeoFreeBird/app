#import "Theme.h"
#import "../HookHelpers.h"

static BOOL updatingTabIconColor = NO;

%hook TAEColorSettings

- (void)setPrimaryColorOption:(NSInteger)colorOption {
    NSNumber* selectedColor = BHTSelectedThemeColor();
    %orig(BHTNativeThemeOption(selectedColor ? selectedColor.integerValue : colorOption));
}

- (NSInteger)primaryColorOption {
    NSNumber* selectedColor = BHTSelectedThemeColor();
    return selectedColor ? BHTNativeThemeOption(selectedColor.integerValue) : %orig;
}

%end

%hook TAELightColorPalette
- (UIColor*)primaryColor {
    return BHTThemePrimaryColor(self, %orig);
}
%end

%hook TAEDarkColorPalette
- (UIColor*)primaryColor {
    return BHTThemePrimaryColor(self, %orig);
}
%end

%hook TAEColorLoader

- (UIColor*)colorForPropertyName:(NSString*)name {
    return BHTThemeLoadedColor(self, name, %orig);
}

%end

%hook TFNDynamicColorManager

- (UIColor*)dynamicColorForObject:(id)object color:(UIColor*)color {
    return BHTThemeDynamicColor(color, %orig);
}

%end

%hook XDSGlass

- (void)layoutSubviews {
    %orig;
    BHTUpdateDimGlass((UIView*)self);
}

- (void)didMoveToWindow {
    %orig;
    BHTUpdateDimGlass((UIView*)self);
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraits {
    %orig;
    BHTUpdateDimGlass((UIView*)self);
}

%end

%hook CAGradientLayer

- (void)setColors:(NSArray*)colors {
    %orig(BHTThemeGradientColors(self, colors));
}

%end

%hook XDSBlur

- (void)layoutSubviews {
    %orig;
    BHTApplyScrollEdgeBlur(self);
}

%end

%hook _TtC13XDesignSystem18ScrollEdgeFadeView

- (void)layoutSubviews {
    %orig;
    BHTApplyScrollEdgeFade(self);
}

%end

%hook TFNGradientView

- (void)layoutSubviews {
    %orig;
    BHTApplyScrollEdgeFade((UIView*)self);
}

- (void)didMoveToWindow {
    %orig;
    BHTApplyScrollEdgeFade((UIView*)self);
}

%end

%hook _TtC13XDesignSystem19ScrollEdgeTreatment

- (void)layoutSubviews {
    %orig;
    if (!BHTDimThemeEnabled()) return;
    BHTApplyDimScrollEdgeChildren(self);
}

%end

%hook TAETwitterColorPaletteSettingInfo

- (id<TAEColorPalette>)colorPalette {
    return BHTThemeColorPalette(self, %orig, self.isDark);
}

%end

%hook UIColor

+ (UIColor*)systemBackgroundColor {
    return BHTThemeSystemBackground(%orig, BHTDimBackgroundColor());
}

+ (UIColor*)secondarySystemBackgroundColor {
    return BHTThemeSystemBackground(%orig, BHTDimElevatedBackgroundColor());
}

+ (UIColor*)tertiarySystemBackgroundColor {
    return BHTThemeSystemBackground(%orig, BHTDimHighlightBackgroundColor());
}

+ (UIColor*)systemGroupedBackgroundColor {
    return BHTThemeSystemBackground(%orig, BHTDimBackgroundColor());
}

+ (UIColor*)secondarySystemGroupedBackgroundColor {
    return BHTThemeSystemBackground(%orig, BHTDimElevatedBackgroundColor());
}

+ (UIColor*)tertiarySystemGroupedBackgroundColor {
    return BHTThemeSystemBackground(%orig, BHTDimHighlightBackgroundColor());
}

%end

%hook UIDynamicSystemColor

- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    return BHTThemeResolvedBackground(%orig, traitCollection);
}

%end

%hook UIDeviceRGBColor
- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    return BHTThemeResolvedBackground(%orig, traitCollection);
}

%end

%hook UIDynamicCatalogColor

- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    return BHTThemeResolvedBackground(%orig, traitCollection);
}

%end

%hook UIExtendedSRGBColorSpace

- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    return BHTThemeResolvedBackground(%orig, traitCollection);
}

%end

%hook UIView

- (void)setBackgroundColor:(UIColor*)color {
    %orig(BHTThemeViewBackground(self, color));
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        BHTRefreshDimBackground(self);
    }

    if (self.window && NFBLiquidGlassEnabled() && BHTDimThemeEnabled() &&
        ([self isKindOfClass:UILabel.class] || [self isKindOfClass:UIImageView.class] ||
         [self isKindOfClass:NSClassFromString(@"TFNButton")])) {
        Class glassClass = NSClassFromString(@"XDSGlass");
        for (UIView* parent = self.superview; parent; parent = parent.superview) {
            if ([parent isKindOfClass:glassClass]) {
                BHTUpdateDimGlass(parent);
                break;
            }
        }
    }
}

%end

%hook TFNSolidColorView

- (void)didMoveToWindow {
    %orig;
    if (((UIView*)self).window) {
        BHTApplyDimSolidColorView((UIView*)self);
    }
}

%end

%hook TFNSearchBar

- (void)layoutSubviews {
    %orig;
    BHTApplyDimSearchPill((UISearchBar*)self);
}

- (void)didMoveToWindow {
    %orig;
    BHTApplyDimSearchPill((UISearchBar*)self);
}

%end

%hook _UITextFieldImageBackgroundView

- (void)setImage:(UIImage*)image {
    if (BHTDimThemeEnabled() && BHTIsExploreSearchBackgroundView((UIView*)self) &&
        ((UIView*)self).traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        %orig(BHTDimSearchPillImage());
    } else {
        %orig(image);
    }
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView*)self).window && BHTDimThemeEnabled() &&
        BHTIsExploreSearchBackgroundView((UIView*)self) &&
        ((UIView*)self).traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        ((UIImageView*)self).image = BHTDimSearchPillImage();
    }
}

%end

%hook _TtC10TFNUISwift26LegacySegmentedTabBarStyle

- (void)setHighlightBarColor:(UIColor*)color {
    if (color && [BHTSettings boolForKey:@"tab_bar_theming"]) {
        %orig(CurrentAccentColor());
        return;
    }
    %orig(color);
}

%end

%hook _TtC10TFNUISwift25LegacySegmentedTabBarView

- (void)setStyle:(_TtC10TFNUISwift26LegacySegmentedTabBarStyle*)style {
    if (style && [BHTSettings boolForKey:@"tab_bar_theming"]) {
        style.highlightBarColor = CurrentAccentColor();
    }
    %orig(style);
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        BHTRefreshSegmentedTabBarColors(self);
    }
}

%end

%hook _TtC10TFNUISwift31LegacySegmentedHighlightBarView

- (void)setBackgroundColor:(UIColor*)color {
    if (color && [BHTSettings boolForKey:@"tab_bar_theming"]) {
        %orig(CurrentAccentColor());
        return;
    }
    %orig(color);
}

%end

%hook _UIBarBackground

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        BHTApplyDimBarBackground(self);
    }
}

%end

%hook T1TabCustomizationViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTApplyDisabledBarButtonTextColor((UIViewController*)self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    BHTApplyDisabledBarButtonTextColor((UIViewController*)self);
}

%end

%hook T1ColorSettings

+ (void)traitCollectionDidChange {
    %orig;
    BHTScheduleDimRefresh();
}

+ (void)_t1_updateOverrideUserInterfaceStyle {
    %orig;
    BHTScheduleDimRefresh();
}

%end

%hook T1TabBarViewController

// The scroll-driven hide only reaches the tab bar as a collapse ratio, so
// clamping it spares the deliberate hides (fullscreen media, immersive player).
- (void)setTabBarCollapseRatio:(double)ratio {
    if ([BHTSettings boolForKey:@"no_tab_bar_hiding"] || NFBLiquidGlassEnabled()) {
        %orig(0.0);
    } else {
        %orig(ratio);
    }
}

%end

%hook _TtC11XNavigation10TabBarView

- (void)layoutSubviews {
    %orig;
    BHTApplyGlassTabLabels((UIView*)self);
}

%new
- (void)nfb_refreshGlassTabLabels {
    BHTApplyGlassTabLabels((UIView*)self);
}

%end

%hook _TtC11XNavigation14TabBarItemView

- (void)layoutSubviews {
    %orig;
    BHTApplyGlassTabAccent((UIView*)self);
    BHTLayoutGlassTabItem((UIView*)self);
}

%new
- (void)nfb_applyGlassTabAccent {
    BHTApplyGlassTabAccent((UIView*)self);
}

%end

%hook T1TabView

- (void)setSelected:(BOOL)selected {
    %orig(selected);
    BHTUpdateLegacyTabLabelColor(self, selected);
}

- (void)layoutSubviews {
    UIView* glyph = BHTPrepareLegacyTabLayout(self);
    %orig;
    BHTFinishLegacyTabLayout(self, glyph);
}

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    if (updatingTabIconColor) return;
    updatingTabIconColor = YES;
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        self.iconColor = BHTTabItemColor(self.selected);
    } else if (self.iconColor) {
        self.iconColor = nil;
    }
    updatingTabIconColor = NO;
    %orig(animated);
    BHTUpdateLegacyTabLabelColor(self, self.selected);
}

- (void)applyTintColor:(UIColor*)color {
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        %orig(BHTTabItemColor(self.selected));
    } else {
        %orig(color);
    }
}

- (void)didMoveToWindow {
    %orig;

    if (self.window) {
        [self setNeedsLayout];
    }
}

%end

%hook _TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin

- (UIView*)titleView {
    UIView* titleView = %orig;

    if ([BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"] &&
        [titleView isKindOfClass:[UIImageView class]]) {
        UIImageView* logoView = (UIImageView*)titleView;
        if (logoView.image) {
            logoView.image = [logoView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            logoView.tintColor = CurrentAccentColor();
            BHTMarkAccentTintedIcon(logoView, YES);
        }
    }

    return titleView;
}

%end
