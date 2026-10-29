//
//  Theme.x
//  NeoFreeBird
//

#import <math.h>
#import <objc/runtime.h>
#import "Headers/TFNHeaders.h"
#import "Headers/UIHeaders.h"
#import "HookHelpers.h"

@interface UIColor (BHTDynamicColorIdentifier)
- (id)tfn_dynamicColorIdentifier;
@end

// MARK: - Custom accent color

static NSNumber* selectedThemeColor(void) {
    return [NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"];
}

static UIColor* selectedCustomThemeColor(void) {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults integerForKey:@"bh_color_theme_selectedColor"] != -1) return nil;
    NSArray* components = [defaults arrayForKey:@"bh_color_theme_customColor"];
    if (components.count != 4) return nil;
    return [UIColor colorWithRed:[components[0] doubleValue]
                           green:[components[1] doubleValue]
                            blue:[components[2] doubleValue]
                           alpha:[components[3] doubleValue]];
}

static NSInteger nativeThemeOption(NSInteger option) {
    // -1 is our custom swatch, not a valid Twitter palette option.
    return option == -1 ? 0 : option;
}

static char BHTNativePrimaryColorKey;
static char BHTLastNativeAccentKey;
static __thread BOOL BHTMappingLoadedColor;
static __thread BOOL BHTMappingDynamicColor;

static UIColor* BHTReplaceNativeAccent(UIColor* color, UIColor* nativeAccent) {
    UIColor* custom = selectedCustomThemeColor();
    if (!custom || ![color isKindOfClass:UIColor.class] ||
        ![nativeAccent isKindOfClass:UIColor.class]) return color;

    UITraitCollection* traits = UITraitCollection.currentTraitCollection;
    UIColor* resolved = [color resolvedColorWithTraitCollection:traits];
    UIColor* native = [nativeAccent resolvedColorWithTraitCollection:traits];
    CGFloat r, g, b, a, nr, ng, nb, na;
    if (![resolved getRed:&r green:&g blue:&b alpha:&a] ||
        ![native getRed:&nr green:&ng blue:&nb alpha:&na] ||
        fabs(r - nr) > 0.004 || fabs(g - ng) > 0.004 ||
        fabs(b - nb) > 0.004) return color;

    return [custom colorWithAlphaComponent:MIN(1.0, custom.CGColor ?
        CGColorGetAlpha(custom.CGColor) * a : a)];
}

// Every apply path (launch re-apply, trait changes, both settings pickers)
// funnels through this setter, so coercing here keeps the custom color pinned.
%hook TAEColorSettings

- (void)setPrimaryColorOption:(NSInteger)colorOption {
    NSNumber* selectedColor = selectedThemeColor();
    %orig(nativeThemeOption(selectedColor ? selectedColor.integerValue : colorOption));
}

- (NSInteger)primaryColorOption {
    NSNumber* selectedColor = selectedThemeColor();
    return selectedColor ? nativeThemeOption(selectedColor.integerValue) : %orig;
}

%end

void applySelectedThemeColor(void) {
    NSNumber* selectedColor = selectedThemeColor();
    if (selectedColor) {
        [[objc_getClass("TAEColorSettings") sharedSettings]
            setPrimaryColorOption:nativeThemeOption(selectedColor.integerValue)];
    }
}

// The native palette supplies most accent-colored controls via primaryColor.
// Keep the six preset getters intact so their picker swatches stay accurate.
%hook TAELightColorPalette
- (UIColor*)primaryColor {
    UIColor* native = %orig;
    objc_setAssociatedObject(self, &BHTNativePrimaryColorKey, native,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return selectedCustomThemeColor() ?: native;
}
%end

%hook TAEDarkColorPalette
- (UIColor*)primaryColor {
    UIColor* native = %orig;
    objc_setAssociatedObject(self, &BHTNativePrimaryColorKey, native,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return selectedCustomThemeColor() ?: native;
}
%end

static UIColor* BHTNativeAccentForCurrentPalette(void) {
    TAEColorSettings* settings = [objc_getClass("TAEColorSettings") sharedSettings];
    id info = settings.currentColorPalette;
    if (!info) return nil;
    UIColor* native = objc_getAssociatedObject(info, &BHTNativePrimaryColorKey);
    if (!native) {
        ((id (*)(id, SEL))objc_msgSend)(info, @selector(colorPalette));
        native = objc_getAssociatedObject(info, &BHTNativePrimaryColorKey);
    }
    return native;
}

static UIColor* BHTNativeAccentForLastPreset(void) {
    NSInteger option = [NSUserDefaults.standardUserDefaults
        integerForKey:@"bh_color_theme_lastNativeColorOption"];
    if (option < 1 || option > 6) return nil;
    TAEColorSettings* settings = [objc_getClass("TAEColorSettings") sharedSettings];
    id info = settings.currentColorPalette;
    if (!info) return nil;
    NSDictionary* cached = objc_getAssociatedObject(info, &BHTLastNativeAccentKey);
    if ([cached[@"option"] integerValue] == option) return cached[@"color"];
    id<TAEColorPalette> palette = ((id (*)(id, SEL))objc_msgSend)(info,
                                                                 @selector(colorPalette));
    UIColor* color = [palette primaryColorForOption:option];
    if (color) {
        objc_setAssociatedObject(info, &BHTLastNativeAccentKey,
                                 @{@"option": @(option), @"color": color},
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return color;
}

static UIColor* BHTReplaceKnownAccent(UIColor* color, UIColor* currentNative) {
    UIColor* mapped = BHTReplaceNativeAccent(color, currentNative);
    return mapped == color
        ? BHTReplaceNativeAccent(color, BHTNativeAccentForLastPreset())
        : mapped;
}

// Named palette colors are resolved by this loader, often from a cached
// preset. Replace colors that match the palette's native accent. The six
// preset swatches stay native because their option properties are excluded.
%hook TAEColorLoader

- (UIColor*)colorForPropertyName:(NSString*)name {
    UIColor* color = %orig;
    if (BHTMappingLoadedColor || !selectedCustomThemeColor() ||
        ![name isKindOfClass:NSString.class] ||
        [name isEqualToString:@"primaryColor"] ||
        [name hasPrefix:@"primaryColorOption"]) return color;

    BHTMappingLoadedColor = YES;
    Ivar paletteField = class_getInstanceVariable(object_getClass(self), "_palette");
    id palette = paletteField ? object_getIvar(self, paletteField) : nil;
    UIColor* native = objc_getAssociatedObject(palette, &BHTNativePrimaryColorKey);
    if (!native && palette &&
        [palette respondsToSelector:@selector(primaryColor)]) {
        // The palette getter records the original color before substituting.
        ((id (*)(id, SEL))objc_msgSend)(palette, @selector(primaryColor));
        native = objc_getAssociatedObject(palette, &BHTNativePrimaryColorKey);
    }
    UIColor* mapped = BHTReplaceKnownAccent(color, native);
    BHTMappingLoadedColor = NO;
    return mapped;
}

%end

// Attributed strings and view setters resolve saved dynamic color identifiers
// through this manager, bypassing the named palette loader above.
%hook TFNDynamicColorManager

- (UIColor*)dynamicColorForObject:(id)object color:(UIColor*)color {
    UIColor* resolved = %orig;
    if (BHTMappingDynamicColor || !selectedCustomThemeColor()) return resolved;
    id identifier = [color respondsToSelector:@selector(tfn_dynamicColorIdentifier)]
        ? [color tfn_dynamicColorIdentifier] : nil;
    // The picker reads these six tokens directly; they are previews, not the
    // active accent, even when the selected option is custom.
    if ([identifier isKindOfClass:NSString.class] &&
        [identifier hasPrefix:@"primaryColorOption"]) return resolved;
    BHTMappingDynamicColor = YES;
    BOOL accentText = [identifier isKindOfClass:NSString.class] &&
        ([identifier isEqualToString:@"primaryColor"] ||
         [identifier isEqualToString:@"textLinkColor"]);
    UIColor* mapped = accentText
        ? BHTReplaceNativeAccent(resolved, resolved)
        : BHTReplaceKnownAccent(resolved, BHTNativeAccentForCurrentPalette());
    BHTMappingDynamicColor = NO;
    return mapped;
}

%end

// MARK: - Dim background recolor

// The app only ever renders Light or Dark now -- there's no native third
// option -- so Dim comes back by intercepting Dark's palette at its one
// choke point and swapping in a proxy that recolors just the background
// family, leaving Light untouched.
%hook TAETwitterColorPaletteSettingInfo

- (id<TAEColorPalette>)colorPalette {
    id<TAEColorPalette> realPalette = %orig;
    if (selectedCustomThemeColor()) {
        UIColor* native = objc_getAssociatedObject(realPalette, &BHTNativePrimaryColorKey);
        if (!native && [(id)realPalette respondsToSelector:@selector(primaryColor)]) {
            ((id (*)(id, SEL))objc_msgSend)(realPalette, @selector(primaryColor));
            native = objc_getAssociatedObject(realPalette, &BHTNativePrimaryColorKey);
        }
        objc_setAssociatedObject(self, &BHTNativePrimaryColorKey, native,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (self.isDark && BHTDimThemeEnabled()) {
        return (id<TAEColorPalette>)[BHTDimPaletteProxy proxyWithPalette:realPalette];
    }
    return realPalette;
}

%end

// Headers, small containers, profile pages, and the boxes around some cells
// don't go through TAEColorPalette at all -- they're drawn with UIKit's own
// dynamic system background colors, which Apple defines as pure black (or
// near enough) in Dark. Re-point those at the same three Dim shades so
// nothing native-styled is left behind.
%hook UIColor

+ (UIColor*)systemBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimBackgroundColor()
                                                                     : original;
    }];
}

+ (UIColor*)secondarySystemBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimElevatedBackgroundColor()
                                                                     : original;
    }];
}

+ (UIColor*)tertiarySystemBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimHighlightBackgroundColor()
                                                                     : original;
    }];
}

+ (UIColor*)systemGroupedBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimBackgroundColor()
                                                                     : original;
    }];
}

+ (UIColor*)secondarySystemGroupedBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimElevatedBackgroundColor()
                                                                     : original;
    }];
}

+ (UIColor*)tertiarySystemGroupedBackgroundColor {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? BHTDimHighlightBackgroundColor()
                                                                     : original;
    }];
}

%end

%hook UIDynamicSystemColor

- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled() || traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return original;
    }
    UIColor* replacement = BHTDimReplacementForResolvedColor(original);
    return replacement ?: original;
}

%end

%hook UIDeviceRGBColor
- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled() || traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return original;
    }
    UIColor* replacement = BHTDimReplacementForResolvedColor(original);
    return replacement ?: original;
}

%end

%hook UIDynamicCatalogColor

- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled() || traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return original;
    }
    UIColor* replacement = BHTDimReplacementForResolvedColor(original);
    return replacement ?: original;
}

%end

%hook UIExtendedSRGBColorSpace

- (UIColor*)resolvedColorWithTraitCollection:(UITraitCollection*)traitCollection {
    UIColor* original = %orig;
    if (!BHTDimThemeEnabled() || traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return original;
    }
    UIColor* replacement = BHTDimReplacementForResolvedColor(original);
    return replacement ?: original;
}

%end

// X 12.9 sometimes assigns backgroundPrimary (or a literal black color) to a
// view after the palette has already been resolved. Reused timeline rows and
// conversation/detail surfaces take this path while scrolling, so the palette
// proxy and private UIColor resolution hooks above never get another chance to
// recolor them. Normalize only UIView background assignments, and repeat the
// normalization when a view enters a window so colors assigned before traits
// were available are covered as well.
static UIColor* BHTDimNormalizedViewBackground(UIView* view, UIColor* color) {
    if (!view || !color || !BHTDimThemeEnabled() ||
        view.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return color;
    }

    UIColor* resolved = [color resolvedColorWithTraitCollection:view.traitCollection];
    UIColor* replacement = BHTDimReplacementForResolvedColor(resolved);
    if (replacement) {
        return replacement;
    }

    // The UIColor hooks may already have resolved a catalog background to a
    // Dim shade. Pin that resolved value on the view so later reuse cannot
    // fall back to the catalog's original pure-black dark variant.
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if ([resolved getRed:&red green:&green blue:&blue alpha:&alpha] && alpha >= 0.99) {
        BOOL isDimShade =
            (fabs(red - 21.0 / 255.0) < 0.002 && fabs(green - 32.0 / 255.0) < 0.002 &&
             fabs(blue - 43.0 / 255.0) < 0.002) ||
            (fabs(red - 25.0 / 255.0) < 0.002 && fabs(green - 39.0 / 255.0) < 0.002 &&
             fabs(blue - 52.0 / 255.0) < 0.002) ||
            (fabs(red - 28.0 / 255.0) < 0.002 && fabs(green - 40.0 / 255.0) < 0.002 &&
             fabs(blue - 54.0 / 255.0) < 0.002);
        if (isDimShade) {
            return resolved;
        }
    }

    return color;
}

%hook UIView

- (void)setBackgroundColor:(UIColor*)color {
    %orig(BHTDimNormalizedViewBackground(self, color));
}

- (void)didMoveToWindow {
    %orig;
    if (self.window && self.backgroundColor) {
        UIColor* normalized = BHTDimNormalizedViewBackground(self, self.backgroundColor);
        if (normalized != self.backgroundColor) {
            self.backgroundColor = normalized;
        }
    }
}

%end

%hook TFNSolidColorView

- (void)didMoveToWindow {
    %orig;
    if (BHTDimThemeEnabled()) {
        self.hidden = TRUE;
    }
}

%end

void BHTApplyDimToVideoControls(UIView* controlsView) {
    if (!BHTDimThemeEnabled() || !controlsView ||
        controlsView.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return;
    }

    controlsView.superview.backgroundColor = BHTDimElevatedBackgroundColor();
}

// X 12.9's Explore search pill is a background image owned by UISearchBar's
// private _UITextFieldImageBackgroundView. It never asks TAEColorPalette for
// pillDefaultBackgroundColor, so recolor it through UISearchBar's public image
// API and preserve the native pill geometry with stretchable round caps.
static UIImage* BHTDimSearchPillImage(void) {
    static UIImage* image;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const CGFloat diameter = 44.0;
        UIGraphicsImageRenderer* renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(diameter, diameter)];
        UIImage* base = [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
            [BHTDimSearchPillColor() setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, diameter, diameter)
                                        cornerRadius:diameter / 2.0] fill];
        }];
        image = [base resizableImageWithCapInsets:UIEdgeInsetsMake(diameter / 2.0,
                                                                   diameter / 2.0,
                                                                   diameter / 2.0,
                                                                   diameter / 2.0)
                                     resizingMode:UIImageResizingModeStretch];
    });
    return image;
}

static void BHTApplyDimSearchPill(UISearchBar* searchBar) {
    if (!BHTDimThemeEnabled() ||
        searchBar.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return;
    }
    [searchBar setSearchFieldBackgroundImage:BHTDimSearchPillImage()
                                    forState:UIControlStateNormal];
}

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

static BOOL BHTIsExploreSearchBackgroundView(UIView* view) {
    Class searchBarClass = objc_getClass("TFNSearchBar");
    for (UIView* ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if (searchBarClass && [ancestor isKindOfClass:searchBarClass]) {
            return YES;
        }
    }
    return NO;
}

// TFNSearchBar reapplies its stock image after -layoutSubviews, so the public
// setter above alone does not survive X's final configuration pass. Intercept
// the concrete UIKit image owner, but only when it belongs to TFNSearchBar.
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
    if (self.window && BHTDimThemeEnabled() && !NFBLiquidGlassEnabled()) {
        self.backgroundColor = BHTDimBackgroundColor();
    }
}

%end

// MARK: - Custom tab bar order and visibility

static NSString* scribePageForEntry(id<T1AppNavigationTabEntry> entry) {
    if (![entry respondsToSelector:@selector(tabView)]) {
        return nil;
    }
    return [entry tabView].scribePage;
}

// Operates on the tab ENTRIES, not the button views: the app derives both the
// buttons and their content view controllers from this one array.
static NSArray* orderedTabEntries(NSArray* entries) {
    // Record the underlying tab views so the editor can show real titles and icons.
    NSMutableArray* tabViews = [NSMutableArray new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        T1TabView* tabView = [entry respondsToSelector:@selector(tabView)] ? [entry tabView] : nil;
        if (tabView) {
            [tabViews addObject:tabView];
        }
    }
    [CustomTabBarUtility recordTabViews:tabViews];

    NSArray<NSString*>* visibleOrder = [CustomTabBarUtility visiblePageIDsInOrder];

    NSMutableDictionary<NSString*, id>* entriesByPage = [NSMutableDictionary new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        NSString* page = scribePageForEntry(entry);
        if (page && !entriesByPage[page]) {
            entriesByPage[page] = entry;
        }
    }

    // Not customised yet: show the default set (Home, Search, Notifications, Chats)
    // in that order, hiding everything else the app builds.
    if (!visibleOrder) {
        NSMutableArray* defaultEntries = [NSMutableArray new];
        for (NSString* pageID in [CustomTabBarUtility defaultVisiblePageIDs]) {
            id entry = entriesByPage[pageID];
            if (entry) {
                [defaultEntries addObject:entry];
            }
        }
        return defaultEntries;
    }

    // Only the chosen tabs show; anything the editor hasn't been told to show
    // (including tabs unlocked after the user last saved) stays hidden.
    NSMutableArray* orderedEntries = [NSMutableArray new];
    NSMutableSet* placed = [NSMutableSet new];
    for (NSString* pageID in visibleOrder) {
        id entry = entriesByPage[pageID];
        if (entry && ![placed containsObject:pageID]) {
            [orderedEntries addObject:entry];
            [placed addObject:pageID];
        }
    }

    return orderedEntries;
}
// The single ordered spine that feeds both the tab buttons and their content, so
// filtering/reordering here keeps taps mapped to the right panel.
%hook T1TabbedAppNavigationViewController

- (void)setVisibleTabEntries:(NSArray*)entries {
    %orig(orderedTabEntries(entries));
}

%end

// MARK: - Keep tab bar visible

%hook T1TabBarViewController

// The scroll-driven hide only reaches the tab bar as a collapse ratio, so
// clamping it spares the deliberate hides (fullscreen media, immersive player).
- (void)setTabBarCollapseRatio:(double)ratio {
    if ([BHTSettings boolForKey:@"no_tab_bar_hiding"]) {
        %orig(0.0);
    } else {
        %orig(ratio);
    }
}

%end

// MARK: - Tab bar icon and label theming

static char BHTGlassTabOriginalTintKey;
static char BHTGlassTabLabelKey;
static char BHTGlassTabOverlayKey;

static void BHTCollectGlassTabItems(UIView* view, Class itemClass,
                                    NSMutableArray<UIView*>* items) {
    for (UIView* subview in view.subviews) {
        if ([subview isKindOfClass:itemClass]) {
            [items addObject:subview];
        } else {
            BHTCollectGlassTabItems(subview, itemClass, items);
        }
    }
}

static NSString* BHTGlassTabItemTitle(UIView* item, UIView* bar) {
    // Reuse the accessibility label
    for (UIView* view = item; view && view != bar; view = view.superview) {
        NSString* title = view.accessibilityLabel;
        if (title.length) return title;
    }
    return nil;
}

static void BHTLayoutGlassTabItem(UIView* item) {
    UILabel* label = objc_getAssociatedObject(item, &BHTGlassTabLabelKey);
    if (!label) return;

    BOOL showLabel = [BHTSettings boolForKey:@"restore_tab_labels"] && label.text.length;
    CGFloat height = CGRectGetHeight(item.bounds);
    CGFloat width = CGRectGetWidth(item.bounds);
    UIView* overlay = label.superview;
    if (overlay.superview && [item isDescendantOfView:overlay.superview]) {
        CGRect frame = CGRectMake(-6.0, height - 13.0, width + 12.0, 11.0);
        label.frame = [item convertRect:frame toView:overlay];
    } else {
        showLabel = NO;
    }
    label.hidden = !showLabel;

    Ivar imageField = class_getInstanceVariable(object_getClass(item), "imageView");
    UIImageView* imageView = imageField ? object_getIvar(item, imageField) : nil;
    if (![imageView isKindOfClass:UIImageView.class]) return;

    UIView* glyph = imageView.superview == item ? imageView : imageView.superview;
    if (glyph.superview != item) return;
    glyph.center = CGPointMake(width / 2.0,
                               height / 2.0 - (showLabel && height >= 34.0 ? 5.0 : 0.0));
}

static void BHTApplyGlassTabLabels(UIView* bar) {
    Class itemClass = NSClassFromString(@"_TtC11XNavigation14TabBarItemView");
    if (!itemClass) return;

    Ivar rowField = class_getInstanceVariable(object_getClass(bar), "itemRow");
    UIView* row = rowField ? object_getIvar(bar, rowField) : nil;
    UIView* container = [row isKindOfClass:UIView.class] ? row : bar;
    NSMutableArray<UIView*>* items = [NSMutableArray new];
    BHTCollectGlassTabItems(container, itemClass, items);
    [items sortUsingComparator:^NSComparisonResult(UIView* first, UIView* second) {
        CGFloat firstX = CGRectGetMidX([first convertRect:first.bounds toView:bar]);
        CGFloat secondX = CGRectGetMidX([second convertRect:second.bounds toView:bar]);
        return firstX < secondX ? NSOrderedAscending
                                : (firstX > secondX ? NSOrderedDescending : NSOrderedSame);
    }];

    NSInteger selectedIndex = NSNotFound;
    Ivar selectedField = class_getInstanceVariable(object_getClass(bar), "selectedIndex");
    if (selectedField) {
        // Swift.Int is pointer-sized on this arm64-only target.
        selectedIndex = *(NSInteger*)((uint8_t*)(__bridge void*)bar +
                                      ivar_getOffset(selectedField));
    }

    BOOL enabled = [BHTSettings boolForKey:@"restore_tab_labels"];
    UIView* overlay = objc_getAssociatedObject(bar, &BHTGlassTabOverlayKey);
    if (!overlay && enabled) {
        overlay = [[UIView alloc] initWithFrame:bar.bounds];
        overlay.userInteractionEnabled = NO;
        overlay.clipsToBounds = NO;
        objc_setAssociatedObject(bar, &BHTGlassTabOverlayKey, overlay,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (overlay && enabled) {
        // The selection pill can cover itemRow; render text above that sibling.
        if (overlay.superview != bar) [bar addSubview:overlay];
        overlay.frame = bar.bounds;
        if (bar.subviews.lastObject != overlay) [bar bringSubviewToFront:overlay];
    }

    NSMutableSet<UILabel*>* activeLabels = [NSMutableSet new];
    for (NSUInteger index = 0; index < items.count; index++) {
        UIView* item = items[index];
        UILabel* label = objc_getAssociatedObject(item, &BHTGlassTabLabelKey);
        NSString* title = enabled ? BHTGlassTabItemTitle(item, bar) : nil;
        if (!label && title.length) {
            label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightMedium];
            label.textAlignment = NSTextAlignmentCenter;
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.7;
            label.lineBreakMode = NSLineBreakByTruncatingTail;
            label.isAccessibilityElement = NO;
            label.userInteractionEnabled = NO;
            objc_setAssociatedObject(item, &BHTGlassTabLabelKey, label,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!label) continue;
        label.text = title;
        label.textColor = (NSInteger)index == selectedIndex
                              ? (CurrentAccentColor() ?: [UIColor labelColor])
                              : [UIColor secondaryLabelColor];
        if (enabled && title.length) {
            if (label.superview != overlay) [overlay addSubview:label];
            [activeLabels addObject:label];
        }
        BHTLayoutGlassTabItem(item);
    }
    for (UIView* subview in [overlay.subviews copy]) {
        if (![activeLabels containsObject:subview]) [subview removeFromSuperview];
    }
    if (!enabled) [overlay removeFromSuperview];
}

static void BHTApplyGlassTabAccent(UIView* item) {
    if (item.isAccessibilityElement) return;

    Ivar field = class_getInstanceVariable(object_getClass(item), "imageView");
    UIImageView* imageView = field ? object_getIvar(item, field) : nil;
    if (![imageView isKindOfClass:UIImageView.class]) return;

    id originalTint = objc_getAssociatedObject(imageView, &BHTGlassTabOriginalTintKey);
    UIColor* tint;
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        if (!originalTint) {
            objc_setAssociatedObject(imageView, &BHTGlassTabOriginalTintKey,
                                     imageView.tintColor ?: (id)NSNull.null,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        tint = CurrentAccentColor();
    } else {
        if (!originalTint) return;
        tint = originalTint == NSNull.null ? nil : originalTint;
        objc_setAssociatedObject(imageView, &BHTGlassTabOriginalTintKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![imageView.tintColor isEqual:tint]) imageView.tintColor = tint;
}

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

static BOOL updatingTabIconColor = NO;
static char BHTLegacyTabLabelKey;
static char BHTLegacyTabGlyphShiftKey;

static UIColor* tabItemColor(BOOL selected) {
    return selected ? CurrentAccentColor() : [UIColor secondaryLabelColor];
}

static void BHTLayoutLegacyTabLabel(T1TabView* tabView) {
    UILabel* label = objc_getAssociatedObject(tabView, &BHTLegacyTabLabelKey);
    BOOL enabled = [BHTSettings boolForKey:@"restore_tab_labels"] && tabView.title.length;
    if (!enabled) {
        [label removeFromSuperview];
        objc_setAssociatedObject(tabView, &BHTLegacyTabLabelKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (!label) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightMedium];
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.7;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.isAccessibilityElement = NO;
        label.userInteractionEnabled = NO;
        objc_setAssociatedObject(tabView, &BHTLegacyTabLabelKey, label,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    label.text = tabView.title;
    label.textColor = tabItemColor(tabView.selected);
    label.frame = CGRectMake(2.0, CGRectGetHeight(tabView.bounds) - 13.0,
                             MAX(0.0, CGRectGetWidth(tabView.bounds) - 4.0), 11.0);
    if (label.superview != tabView) [tabView addSubview:label];
    [tabView bringSubviewToFront:label];
}

%hook T1TabView

- (void)setSelected:(BOOL)selected {
    %orig(selected);
    UILabel* label = objc_getAssociatedObject(self, &BHTLegacyTabLabelKey);
    label.textColor = tabItemColor(selected);
}

- (void)layoutSubviews {
    // Undo previous offset before the app lays out the icon again
    UIView* glyph = self.transformContainer ?: self.imageView;
    if ([objc_getAssociatedObject(glyph, &BHTLegacyTabGlyphShiftKey) boolValue]) {
        glyph.center = CGPointMake(glyph.center.x, glyph.center.y + 5.0);
        objc_setAssociatedObject(glyph, &BHTLegacyTabGlyphShiftKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
    BHTLayoutLegacyTabLabel(self);
    if ([BHTSettings boolForKey:@"restore_tab_labels"] && self.title.length &&
        CGRectGetHeight(self.bounds) >= 34.0 && glyph) {
        glyph.center = CGPointMake(glyph.center.x, glyph.center.y - 5.0);
        objc_setAssociatedObject(glyph, &BHTLegacyTabGlyphShiftKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    if (updatingTabIconColor) return;
    updatingTabIconColor = YES;
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        self.iconColor = tabItemColor(self.selected);
    } else if (self.iconColor) {
        self.iconColor = nil;
    }
    updatingTabIconColor = NO;
    %orig(animated);
    UILabel* label = objc_getAssociatedObject(self, &BHTLegacyTabLabelKey);
    label.textColor = tabItemColor(self.selected);
}

- (void)applyTintColor:(UIColor*)color {
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        %orig(tabItemColor(self.selected));
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

// MARK: - Top bar logo theming

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

// MARK: - iPad sidebar logo theming

static void ApplySidebarIconTheme(UIViewController* sidebar) {
    Ivar iconViewIvar =
        class_getInstanceVariable(%c(T1AppSplitSideBarViewController), "_iconView");
    if (!iconViewIvar) {
        return;
    }

    UIImageView* iconView = object_getIvar(sidebar, iconViewIvar);
    if (![iconView isKindOfClass:[UIImageView class]] || !iconView.image) {
        return;
    }

    BOOL wantsAccent = [BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"];
    UIImageRenderingMode mode = wantsAccent ? UIImageRenderingModeAlwaysTemplate
                                            : UIImageRenderingModeAlwaysOriginal;

    if (iconView.image.renderingMode != mode) {
        iconView.image = [iconView.image imageWithRenderingMode:mode];
    }
    if (wantsAccent) {
        iconView.tintColor = CurrentAccentColor();
    }
    BHTMarkAccentTintedIcon(iconView, wantsAccent);
}

%hook T1AppSplitSideBarViewController

- (void)viewDidLoad {
    %orig;
    ApplySidebarIconTheme(self);
}

- (void)viewWillLayoutSubviews {
    %orig;
    ApplySidebarIconTheme(self);
}

%end
