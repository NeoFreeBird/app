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

@interface BHTDimGlassPlacement : NSObject
@property (nonatomic, weak) UIView* originalParent;
@property (nonatomic) NSUInteger originalIndex;
@property (nonatomic) UIViewAutoresizing originalAutoresizingMask;
@property (nonatomic, strong) UIView* toastTint;
@end
@implementation BHTDimGlassPlacement
@end

static char BHTDimGlassPlacementKey;

static BOOL BHTDimGlassIsInContainer(UIView* glass, NSString* className) {
    Class container = NSClassFromString(className);
    for (UIView* view = glass.superview; view; view = view.superview) {
        if ([view isKindOfClass:container]) return YES;
    }
    return NO;
}

static BOOL BHTDimGlassContainsForeground(UIView* host) {
    Class buttonClass = NSClassFromString(@"TFNButton");
    NSMutableArray<UIView*>* pending = [host.subviews mutableCopy];
    while (pending.count) {
        UIView* view = pending.lastObject;
        [pending removeLastObject];
        if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] ||
            [view isKindOfClass:buttonClass]) return YES;
        [pending addObjectsFromArray:view.subviews];
    }
    return NO;
}


static void BHTUpdateDimGlass(UIView* glass) {
    SEL selector = @selector(contentView);
    if (![glass respondsToSelector:selector]) return;
    UIView* host = ((id (*)(id, SEL))objc_msgSend)(glass, selector);
    if (![host isKindOfClass:UIView.class]) return;

    BHTDimGlassPlacement* placement = objc_getAssociatedObject(glass, &BHTDimGlassPlacementKey);
    BOOL toast = BHTDimGlassIsInContainer(glass, @"XDSToastContainerView");
    BOOL enabled = NFBLiquidGlassEnabled() && BHTDimThemeEnabled() &&
        glass.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark &&
        (toast || BHTDimGlassIsInContainer(glass, @"XDSButton") ||
         BHTDimGlassContainsForeground(host));
    if (!enabled) {
        [placement.toastTint removeFromSuperview];
        UIView* parent = placement.originalParent;
        if (parent && host.superview == glass) {
            CGRect frame = [glass convertRect:host.frame toView:parent];
            [parent insertSubview:host atIndex:MIN(placement.originalIndex, parent.subviews.count)];
            host.frame = frame;
            host.autoresizingMask = placement.originalAutoresizingMask;
        }
        objc_setAssociatedObject(glass, &BHTDimGlassPlacementKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (!placement) {
        UIView* parent = host.superview;
        UIVisualEffectView* effect = [parent.superview isKindOfClass:UIVisualEffectView.class]
            ? (UIVisualEffectView*)parent.superview : nil;
        if (!effect || parent != effect.contentView ||
            ![effect.effect isKindOfClass:NSClassFromString(@"UIGlassEffect")] ||
            !host.translatesAutoresizingMaskIntoConstraints) return;
        for (NSLayoutConstraint* constraint in parent.constraints) {
            if (constraint.active && (constraint.firstItem == host || constraint.secondItem == host)) return;
        }
        placement = [BHTDimGlassPlacement new];
        placement.originalParent = parent;
        placement.originalIndex = [parent.subviews indexOfObjectIdenticalTo:host];
        placement.originalAutoresizingMask = host.autoresizingMask;
        CGRect frame = [parent convertRect:host.frame toView:glass];
        objc_setAssociatedObject(glass, &BHTDimGlassPlacementKey, placement,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [glass addSubview:host];
        host.frame = frame;
        host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }

    if (!toast && placement.toastTint.superview) {
        [placement.toastTint removeFromSuperview];
    } else if (toast && host.superview == glass) {
        if (!placement.toastTint) {
            UIView* tint = [[UIView alloc] initWithFrame:host.bounds];
            tint.userInteractionEnabled = NO;
            tint.isAccessibilityElement = NO;
            tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            tint.backgroundColor = [BHTDimElevatedBackgroundColor() colorWithAlphaComponent:0.75];
            placement.toastTint = tint;
        }
        if (placement.toastTint.superview != host) [host insertSubview:placement.toastTint atIndex:0];
        if (host.subviews.firstObject != placement.toastTint) [host sendSubviewToBack:placement.toastTint];
        placement.toastTint.frame = host.bounds;
    }
    if (host.superview == glass && glass.subviews.lastObject != host) [glass bringSubviewToFront:host];
}

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

static BOOL BHTIsInsideScrollEdgeTreatment(UIView* view) {
    Class treatmentClass = NSClassFromString(@"_TtC13XDesignSystem19ScrollEdgeTreatment");
    for (UIView* parent = view.superview; parent; parent = parent.superview) {
        if ([parent isKindOfClass:treatmentClass]) return YES;
    }
    return NO;
}

static UIColor* BHTDimScrollEdgeColor(UIColor* color, UITraitCollection* traits) {
    if (!BHTDimThemeEnabled() ||
        traits.userInterfaceStyle != UIUserInterfaceStyleDark ||
        ![color isKindOfClass:UIColor.class]) return nil;

    UIColor* resolved = [color resolvedColorWithTraitCollection:traits];
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if (![resolved getRed:&red green:&green blue:&blue alpha:&alpha] ||
        alpha <= 0.01 ||
        MAX(red, MAX(green, blue)) > 0.25 ||
        MAX(red, MAX(green, blue)) - MIN(red, MIN(green, blue)) > 0.04) return nil;
    return [BHTDimBackgroundColor() colorWithAlphaComponent:alpha];
}

static BOOL BHTIsScrollEdgeBlurTintView(UIView* view) {
    Class blurClass = NSClassFromString(@"XDSBlur");
    for (UIView* parent = view.superview; parent; parent = parent.superview) {
        if (![parent isKindOfClass:blurClass]) continue;
        Ivar tintField = class_getInstanceVariable(object_getClass(parent), "tintView");
        return tintField && object_getIvar(parent, tintField) == view &&
               BHTIsInsideScrollEdgeTreatment(parent);
    }
    return NO;
}

// A flat Dim color pinned in Dark can't follow a live switch back to Light, so
// remember the color it replaced. NSNull stands for a nil background.
static char BHTDimOriginalBackgroundKey;

static void BHTSaveDimOriginalBackground(UIView* view, UIColor* original) {
    objc_setAssociatedObject(view, &BHTDimOriginalBackgroundKey, original ?: (id)NSNull.null,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void BHTApplyScrollEdgeBlur(XDSBlur* blur) {
    if (!BHTIsInsideScrollEdgeTreatment(blur)) return;
    Ivar tintField = class_getInstanceVariable(object_getClass(blur), "tintView");
    UIView* tintView = tintField ? object_getIvar(blur, tintField) : nil;
    if (![tintView isKindOfClass:UIView.class]) return;
    UIColor* original = tintView.backgroundColor;
    UIColor* dim = BHTDimScrollEdgeColor(original, blur.traitCollection);
    if (dim) {
        tintView.backgroundColor = dim;
        BHTSaveDimOriginalBackground(tintView, original);
    }
}

// Reads the CGColor directly: going through UIColor resolution would hit the
// Dim hooks above, which turn opaque black into a navy this filter rejects.
// Transparent stops are recolored too, since their RGB still shows along the fade.
static UIColor* BHTDimFadeGradientColor(CGColorRef color, UITraitCollection* traits) {
    if (!BHTDimThemeEnabled() || traits.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return nil;
    }

    size_t count = CGColorGetNumberOfComponents(color);
    const CGFloat* components = CGColorGetComponents(color);
    if (!components || (count != 2 && count != 4)) return nil;

    CGFloat red = components[0];
    CGFloat green = count == 4 ? components[1] : red;
    CGFloat blue = count == 4 ? components[2] : red;
    CGFloat alpha = components[count - 1];
    CGFloat maxComponent = MAX(red, MAX(green, blue));
    if (maxComponent > 0.25 || maxComponent - MIN(red, MIN(green, blue)) > 0.04) return nil;
    return [BHTDimBackgroundColor() colorWithAlphaComponent:alpha];
}

static BOOL BHTIsDimFadeView(UIView* view) {
    // TFNGradientView also darkens media overlays, so only match the composer's
    // button bar, where it fades the scrolling buttons into the background.
    Class gradientClass = NSClassFromString(@"TFNGradientView");
    Class buttonBarClass = NSClassFromString(@"TFNButtonBarView");
    if (gradientClass && buttonBarClass && [view isKindOfClass:gradientClass] &&
        [view.superview isKindOfClass:buttonBarClass]) return YES;

    Class fadeClass = NSClassFromString(@"_TtC13XDesignSystem18ScrollEdgeFadeView");
    return fadeClass && [view isKindOfClass:fadeClass] && BHTIsInsideScrollEdgeTreatment(view);
}

static void BHTApplyScrollEdgeFade(UIView* fade) {
    if (!BHTIsDimFadeView(fade) || !BHTDimThemeEnabled() ||
        fade.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) return;

    Ivar gradientField = class_getInstanceVariable(object_getClass(fade), "gradientLayer");
    CAGradientLayer* gradient = gradientField ? object_getIvar(fade, gradientField)
                                              : (CAGradientLayer*)fade.layer;
    if (![gradient isKindOfClass:CAGradientLayer.class]) return;

    NSArray* colors = gradient.colors;
    if (!colors.count) return;
    NSMutableArray* mapped = [NSMutableArray arrayWithCapacity:colors.count];
    BOOL changed = NO;
    for (id entry in colors) {
        CGColorRef cgColor = (__bridge CGColorRef)entry;
        UIColor* dim = BHTDimFadeGradientColor(cgColor, fade.traitCollection);
        [mapped addObject:dim ? (__bridge id)dim.CGColor : entry];
        changed |= dim != nil;
    }
    if (changed) gradient.colors = mapped;
}

%hook CAGradientLayer

- (void)setColors:(NSArray*)colors {
    // TFNGradientView is backed by the gradient layer itself.
    UIView* owner = [(id)self.delegate isKindOfClass:NSClassFromString(@"TFNGradientView")]
        ? (UIView*)self.delegate
        : (UIView*)self.superlayer.delegate;
    if (![owner isKindOfClass:UIView.class] || !BHTIsDimFadeView(owner) ||
        !BHTDimThemeEnabled() ||
        owner.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        %orig;
        return;
    }

    NSMutableArray* mapped = [NSMutableArray arrayWithCapacity:colors.count];
    for (id entry in colors) {
        UIColor* dim = BHTDimFadeGradientColor((__bridge CGColorRef)entry, owner.traitCollection);
        [mapped addObject:dim ? (__bridge id)dim.CGColor : entry];
    }
    %orig(mapped);
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

static void BHTApplyDimScrollEdgeChildren(UIView* treatment) {
    Class blurClass = NSClassFromString(@"XDSBlur");
    Class fadeClass = NSClassFromString(@"_TtC13XDesignSystem18ScrollEdgeFadeView");
    NSMutableArray<UIView*>* pending = [treatment.subviews mutableCopy];
    while (pending.count) {
        UIView* view = pending.lastObject;
        [pending removeLastObject];
        if (blurClass && [view isKindOfClass:blurClass]) {
            BHTApplyScrollEdgeBlur((XDSBlur*)view);
        } else if (fadeClass && [view isKindOfClass:fadeClass]) {
            BHTApplyScrollEdgeFade(view);
        }
        [pending addObjectsFromArray:view.subviews];
    }
}

%hook _TtC13XDesignSystem19ScrollEdgeTreatment

- (void)layoutSubviews {
    %orig;
    if (!BHTDimThemeEnabled()) return;
    BHTApplyDimScrollEdgeChildren(self);
}

%end

// The app only ever renders Light or Dark now -- there's no native third
// option -- so Dim comes back by intercepting Dark's palette at its one
// choke point and swapping in a proxy that recolors just the background
// family, leaving Light untouched.
// Set once the Dim palette has been handed out, so the restore paths know
// there may be Dim colors to undo even after the setting is turned off.
static BOOL BHTDimHasRendered;
static char BHTDimProxyKey;

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
        BHTDimHasRendered = YES;
        // One proxy per real palette: this getter runs on hot paths.
        BHTDimPaletteProxy* proxy = objc_getAssociatedObject(realPalette, &BHTDimProxyKey);
        if (!proxy) {
            proxy = [BHTDimPaletteProxy proxyWithPalette:realPalette];
            objc_setAssociatedObject(realPalette, &BHTDimProxyKey, proxy,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return (id<TAEColorPalette>)proxy;
    }
    return realPalette;
}

%end

// Headers, small containers, profile pages, and the boxes around some cells
// don't go through TAEColorPalette at all -- they're drawn with UIKit's own
// dynamic system background colors, which Apple defines as pure black (or
// near enough) in Dark. Re-point those at the same three Dim shades so
// nothing native-styled is left behind.
// Dim can be turned off while the app runs, so the provider checks the setting
// on every resolve rather than only when the color was created.
static UIColor* BHTDimSystemColor(UIColor* original, UIColor* (*dimShade)(void)) {
    if (!BHTDimThemeEnabled()) {
        return original;
    }
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return BHTDimThemeEnabled() && traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? dimShade() : original;
    }];
}

%hook UIColor

+ (UIColor*)systemBackgroundColor {
    return BHTDimSystemColor(%orig, BHTDimBackgroundColor);
}

+ (UIColor*)secondarySystemBackgroundColor {
    return BHTDimSystemColor(%orig, BHTDimElevatedBackgroundColor);
}

+ (UIColor*)tertiarySystemBackgroundColor {
    return BHTDimSystemColor(%orig, BHTDimHighlightBackgroundColor);
}

+ (UIColor*)systemGroupedBackgroundColor {
    return BHTDimSystemColor(%orig, BHTDimBackgroundColor);
}

+ (UIColor*)secondarySystemGroupedBackgroundColor {
    return BHTDimSystemColor(%orig, BHTDimElevatedBackgroundColor);
}

+ (UIColor*)tertiarySystemGroupedBackgroundColor {
    return BHTDimSystemColor(%orig, BHTDimHighlightBackgroundColor);
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
static BOOL BHTColorIsDimShade(UIColor* color) {
    return BHTDimShadeOfColor(color) != BHTDimShadeNone;
}

// TFNButton keeps its own background color per state and never passes an
// assigned color to UIView: it stores it as the normal, highlighted and
// disabled colors, then reapplies them whenever the palette reloads. Its
// colors already come from the palette, so Dim reaches it through the proxy;
// recoloring it here would replace the button's own colors for good.
static BOOL BHTDimLeavesBackgroundAlone(UIView* view) {
    static Class buttonClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        buttonClass = NSClassFromString(@"TFNButton");
    });
    return buttonClass && [view isKindOfClass:buttonClass];
}

static UIColor* BHTDimNormalizedBackground(UIView* view, UIColor* color,
                                           UITraitCollection* traits) {
    if (!view || !color || !BHTDimThemeEnabled() ||
        traits.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return color;
    }

    if (BHTIsScrollEdgeBlurTintView(view)) {
        UIColor* dimTint = BHTDimScrollEdgeColor(color, traits);
        if (dimTint) return dimTint;
    }

    UIColor* resolved = [color resolvedColorWithTraitCollection:traits];
    UIColor* replacement = BHTDimReplacementForResolvedColor(resolved);
    if (replacement) {
        return BHTDimColorPreservingIdentifier(replacement, color);
    }

    // The UIColor hooks may already have resolved a catalog background to a
    // Dim shade. Pin that resolved value on the view so later reuse cannot
    // fall back to the catalog's original pure-black dark variant.
    if (BHTColorIsDimShade(resolved)) {
        return resolved;
    }

    return color;
}

static UIColor* BHTDimNormalizedViewBackground(UIView* view, UIColor* color) {
    return BHTDimNormalizedBackground(view, color, view.traitCollection);
}

static UIColor* BHTCurrentPaletteColorForDimShade(BHTDimShadeKind shade);

// When the app is not rendering Dim -- Light, or Dark with Dim turned off --
// returns the palette color that stands in for a Dim shade; nil otherwise.
// The app switches its palette before every view reports the new appearance
// (thread replies still on screen can claim Dark once the app is Light), so
// this asks the palette, not the view. It runs on hot paths, so it answers from
// the palette's isDark flag: reading the Dark palette would build a Dim proxy
// on every call just to say no.
static UIColor* BHTPaletteReplacementForDimShade(UIColor* color) {
    BHTDimShadeKind shade = BHTDimShadeOfColor(color);
    if (shade == BHTDimShadeNone) return nil;
    TAETwitterColorPaletteSettingInfo* info =
        [[objc_getClass("TAEColorSettings") sharedSettings] currentColorPalette];
    if (!info || (info.isDark && BHTDimThemeEnabled())) return nil;
    return BHTCurrentPaletteColorForDimShade(shade);
}

// A dynamic color reads as whatever the current appearance resolves it to, so
// a Dim reading alone doesn't make it flat: it must be Dim in Light as well.
static BOOL BHTColorIsFlatDimShade(UIColor* color) {
    static UITraitCollection* light;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        light = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight];
    });
    return BHTColorIsDimShade(color) &&
           BHTColorIsDimShade([color resolvedColorWithTraitCollection:light]);
}

static UIColor* BHTPaletteReloadedColor(UIColor* color);

// X reloads a view's palette colors only when its traits change, and a Dim
// toggle leaves the traits where they were, so views off screen at the time
// (another tab's list, cells waiting for reuse) would keep the old colors.
// Each toggle starts a new generation; a view from an older one has its
// background re-read from the palette when it is next refreshed.
static NSUInteger BHTDimGeneration;
static char BHTDimSeenGenerationKey;

static BOOL BHTDimMarkSeen(UIView* view) {
    if (!BHTDimGeneration) return NO;
    NSNumber* seen = objc_getAssociatedObject(view, &BHTDimSeenGenerationKey);
    if (seen.unsignedIntegerValue == BHTDimGeneration) return NO;
    objc_setAssociatedObject(view, &BHTDimSeenGenerationKey, @(BHTDimGeneration),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

// Brings one view's background in line with the app's appearance: applies Dim
// while the app renders it, and otherwise puts back the color Dim replaced.
// Some surfaces, such as thread replies, hold a flat copy of the Dim color with
// nothing saved; they get the palette's color, whose identifier lets the app
// handle later switches. Views off screen during a switch (another tab's list)
// are caught here when they come back into a window.
// `traits` stands in for the view's own: during a switch a view can still
// report the previous appearance while the palette has already moved on.
static void BHTRefreshDimBackgroundAs(UIView* view, UITraitCollection* traits) {
    // Until Dim has rendered in this process, there is nothing to undo.
    if (!BHTDimThemeEnabled() && !BHTDimHasRendered) return;
    if (BHTDimLeavesBackgroundAlone(view)) return;

    if (BHTDimMarkSeen(view)) {
        // A palette color from before the toggle: the setter hook below then
        // applies or skips Dim for the reloaded value.
        UIColor* reloaded = BHTPaletteReloadedColor(view.backgroundColor);
        if (reloaded) view.backgroundColor = reloaded;
    }

    UIColor* current = view.backgroundColor;
    if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) {
        UIColor* normalized = current ? BHTDimNormalizedBackground(view, current, traits) : nil;
        if (!BHTPaletteReplacementForDimShade(normalized)) {
            if (normalized != current) {
                // Assign the converted color itself: the setter hook would
                // normalize with the view's own traits, not with `traits`.
                if (!BHTColorIsFlatDimShade(current)) BHTSaveDimOriginalBackground(view, current);
                view.backgroundColor = normalized;
            }
            return;
        }
    }

    id saved = objc_getAssociatedObject(view, &BHTDimOriginalBackgroundKey);
    if (saved) {
        view.backgroundColor = [saved isKindOfClass:UIColor.class] ? saved : nil;
        objc_setAssociatedObject(view, &BHTDimOriginalBackgroundKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    // During a switch the palette can still be the previous one; the delayed
    // refresh retries once it has settled. Only a flat copy of a Dim shade is
    // replaced: resolving with Dark traits would run any near-black color, such
    // as the Follow button's fill in Light, through Dim's own conversion.
    if (!BHTColorIsFlatDimShade(current)) return;
    UIColor* replacement = BHTPaletteReplacementForDimShade(current);
    if (replacement) view.backgroundColor = replacement;
}

// The palette is the authority in both directions. Once the app renders Dim,
// every view is refreshed as Dark, whatever it reports itself: a view entering
// a window, or a cell prepared off screen, can still carry Light or no traits.
// Mirrors the Light handling in BHTPaletteReplacementForDimShade.
static UITraitCollection* BHTDimAuthorityTraits(void) {
    if (!BHTDimThemeEnabled()) return nil;
    TAETwitterColorPaletteSettingInfo* info =
        [[objc_getClass("TAEColorSettings") sharedSettings] currentColorPalette];
    if (!info.isDark) return nil;
    static UITraitCollection* dark;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dark = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark];
    });
    return dark;
}

static void BHTRefreshDimBackground(UIView* view) {
    BHTRefreshDimBackgroundAs(view, BHTDimAuthorityTraits() ?: view.traitCollection);
}

%hook UIView

- (void)setBackgroundColor:(UIColor*)color {
    // Nothing to apply or undo until Dim has rendered in this process.
    if ((!BHTDimThemeEnabled() && !BHTDimHasRendered) || BHTDimLeavesBackgroundAlone(self)) {
        %orig(color);
        return;
    }
    UIColor* normalized = BHTDimNormalizedViewBackground(self, color);
    // The app is not rendering Dim, or the view still reports Dark after the
    // switch: a flat Dim color takes the palette's color, any other stays as
    // assigned. Reading a dynamic color's components resolves it with the
    // current traits, still Dark during a switch, which would run a near-black
    // color such as the Follow button's Light fill through Dim's conversion.
    UIColor* replacement = BHTPaletteReplacementForDimShade(normalized);
    if (replacement) normalized = BHTColorIsFlatDimShade(color) ? replacement : color;
    if (normalized != color) {
        // A color that's already Dim has nothing worth restoring in Light; a
        // dynamic one does, since it adapts to Light on its own.
        if (!BHTColorIsFlatDimShade(color)) {
            BHTSaveDimOriginalBackground(self, color);
        }
    } else if (objc_getAssociatedObject(self, &BHTDimOriginalBackgroundKey) &&
               !BHTColorIsFlatDimShade(color)) {
        // The app assigned a new color of its own, which supersedes the saved one.
        objc_setAssociatedObject(self, &BHTDimOriginalBackgroundKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig(normalized);
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

static char BHTDimHidSolidColorViewKey;

// Dim only recolors Dark, so these views are hidden in Dark alone. The flag
// records which ones Dim hid, so views the app hid itself stay hidden in Light.
static void BHTApplyDimSolidColorView(UIView* view) {
    if (BHTDimThemeEnabled() &&
        view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        if (!view.hidden) {
            objc_setAssociatedObject(view, &BHTDimHidSolidColorViewKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            view.hidden = YES;
        }
    } else if (objc_getAssociatedObject(view, &BHTDimHidSolidColorViewKey)) {
        objc_setAssociatedObject(view, &BHTDimHidSolidColorViewKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.hidden = NO;
    }
}

%hook TFNSolidColorView

- (void)didMoveToWindow {
    %orig;
    if (((UIView*)self).window) {
        BHTApplyDimSolidColorView((UIView*)self);
    }
}

%end

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

static char BHTDimSearchPillAppliedKey;

static void BHTApplyDimSearchPill(UISearchBar* searchBar) {
    if (BHTDimThemeEnabled() &&
        searchBar.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        objc_setAssociatedObject(searchBar, &BHTDimSearchPillAppliedKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [searchBar setSearchFieldBackgroundImage:BHTDimSearchPillImage()
                                        forState:UIControlStateNormal];
    } else if (objc_getAssociatedObject(searchBar, &BHTDimSearchPillAppliedKey)) {
        objc_setAssociatedObject(searchBar, &BHTDimSearchPillAppliedKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [searchBar setSearchFieldBackgroundImage:nil forState:UIControlStateNormal];
    }
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

@protocol BHTDimTextPalette <NSObject>
- (UIColor*)textColor;
- (UIColor*)textDetailsColor;
- (UIColor*)dynamicColorWithIdentifier:(id)identifier;
- (UIColor*)backgroundColor;
- (UIColor*)elevatedBackgroundColor;
- (UIColor*)highlightBackgroundColor;
@end

@interface _TtC10TFNUISwift25LegacySegmentedTabBarView (BHTDimRefresh)
- (void)reloadVisibleTabs;
@end

static UIColor* BHTCurrentPaletteColor(id<BHTDimTextPalette> palette, UIColor* color,
                                       UIColor* fallback) {
    id identifier = [color respondsToSelector:@selector(tfn_dynamicColorIdentifier)]
        ? [color tfn_dynamicColorIdentifier] : nil;
    UIColor* reloaded = identifier && [palette respondsToSelector:@selector(dynamicColorWithIdentifier:)]
        ? [palette dynamicColorWithIdentifier:identifier] : nil;
    return reloaded ?: fallback;
}

static id<BHTDimTextPalette> BHTCurrentTextPalette(void) {
    id info = [[objc_getClass("TAEColorSettings") sharedSettings] currentColorPalette];
    return info ? ((id (*)(id, SEL))objc_msgSend)(info, @selector(colorPalette)) : nil;
}

// The palette's current value for a color carrying a dynamic color identifier,
// nil for any other color.
static UIColor* BHTPaletteReloadedColor(UIColor* color) {
    return BHTCurrentPaletteColor(BHTCurrentTextPalette(), color, nil);
}

static UIColor* BHTCurrentPaletteColorForDimShade(BHTDimShadeKind shade) {
    id<BHTDimTextPalette> palette = BHTCurrentTextPalette();
    switch (shade) {
        case BHTDimShadeElevated:
            return palette.elevatedBackgroundColor;
        case BHTDimShadeHighlight:
            return palette.highlightBackgroundColor;
        default:
            return palette.backgroundColor;
    }
}

// X's tab customization screen leaves its disabled Save button nearly invisible
// on the Dim background, so give the disabled state the secondary text color.
static void BHTApplyDisabledBarButtonTextColor(UIViewController* controller) {
    UIColor* disabledColor = BHTDimThemeEnabled() ? BHTCurrentTextPalette().textDetailsColor : nil;
    if (!disabledColor) return;

    for (UIBarButtonItem* item in controller.navigationItem.rightBarButtonItems) {
        if (![[item titleTextAttributesForState:UIControlStateDisabled]
                [NSForegroundColorAttributeName] isEqual:disabledColor]) {
            [item setTitleTextAttributes:@{NSForegroundColorAttributeName: disabledColor}
                                forState:UIControlStateDisabled];
        }
        if ([item.customView isKindOfClass:UIButton.class]) {
            UIButton* button = (UIButton*)item.customView;
            if (![[button titleColorForState:UIControlStateDisabled] isEqual:disabledColor]) {
                [button setTitleColor:disabledColor forState:UIControlStateDisabled];
            }
        }
    }
}

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

static char BHTSegmentedTabBarAppearanceKey;

// The tab bar's style holds its title colors from when it was built, so they
// have to be fetched again from the new palette after an appearance change.
static void BHTRefreshSegmentedTabBarColors(_TtC10TFNUISwift25LegacySegmentedTabBarView* tabBar) {
    if (!BHTDimThemeEnabled() && !BHTDimHasRendered) return;

    NSNumber* current = @(tabBar.traitCollection.userInterfaceStyle);
    NSNumber* previous = objc_getAssociatedObject(tabBar, &BHTSegmentedTabBarAppearanceKey);
    if ([previous isEqualToNumber:current]) return;
    objc_setAssociatedObject(tabBar, &BHTSegmentedTabBarAppearanceKey, current,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!previous) return;

    _TtC10TFNUISwift26LegacySegmentedTabBarStyle* style = tabBar.style;
    id<BHTDimTextPalette> palette = BHTCurrentTextPalette();
    if (!style || !palette) return;

    style.selectedTextColor =
        BHTCurrentPaletteColor(palette, style.selectedTextColor, palette.textColor);
    style.deselectedTextColor =
        BHTCurrentPaletteColor(palette, style.deselectedTextColor, palette.textDetailsColor);
    tabBar.style = style;
    // Private, so another X build may not have it; then the tabs pick the new
    // colors up on their next layout instead.
    if ([tabBar respondsToSelector:@selector(reloadVisibleTabs)]) {
        [tabBar reloadVisibleTabs];
    }
}

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

static void BHTApplyDimBarBackground(UIView* bar) {
    if (!BHTDimThemeEnabled() || NFBLiquidGlassEnabled() ||
        bar.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return;
    }
    UIColor* original = bar.backgroundColor;
    if (BHTColorIsDimShade(original)) return;
    bar.backgroundColor = BHTDimBackgroundColor();
    BHTSaveDimOriginalBackground(bar, original);
}

%hook _UIBarBackground

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        BHTApplyDimBarBackground(self);
    }
}

%end

// MARK: - Live appearance changes

static void BHTRefreshDimView(UIView* view, UITraitCollection* traits) {
    static Class barClass, solidClass, searchBarClass, blurClass, fadeClass, tabBarClass,
        gradientClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        barClass = NSClassFromString(@"_UIBarBackground");
        solidClass = NSClassFromString(@"TFNSolidColorView");
        searchBarClass = NSClassFromString(@"TFNSearchBar");
        blurClass = NSClassFromString(@"XDSBlur");
        fadeClass = NSClassFromString(@"_TtC13XDesignSystem18ScrollEdgeFadeView");
        tabBarClass = NSClassFromString(@"_TtC10TFNUISwift25LegacySegmentedTabBarView");
        gradientClass = NSClassFromString(@"TFNGradientView");
    });

    BHTRefreshDimBackgroundAs(view, traits ?: view.traitCollection);
    if (barClass && [view isKindOfClass:barClass]) {
        BHTApplyDimBarBackground(view);
    } else if (solidClass && [view isKindOfClass:solidClass]) {
        BHTApplyDimSolidColorView(view);
    } else if (searchBarClass && [view isKindOfClass:searchBarClass]) {
        BHTApplyDimSearchPill((UISearchBar*)view);
    } else if (blurClass && [view isKindOfClass:blurClass]) {
        BHTApplyScrollEdgeBlur((XDSBlur*)view);
    } else if ((fadeClass && [view isKindOfClass:fadeClass]) ||
               (gradientClass && [view isKindOfClass:gradientClass])) {
        BHTApplyScrollEdgeFade(view);
    } else if (tabBarClass && [view isKindOfClass:tabBarClass]) {
        BHTRefreshSegmentedTabBarColors((_TtC10TFNUISwift25LegacySegmentedTabBarView*)view);
    }
}

static void BHTRefreshDimInView(UIView* root, UITraitCollection* traits) {
    NSMutableArray<UIView*>* pending = [NSMutableArray arrayWithObject:root];
    while (pending.count) {
        UIView* view = pending.lastObject;
        [pending removeLastObject];
        BHTRefreshDimView(view, traits);
        [pending addObjectsFromArray:view.subviews];
    }
}

static void BHTRefreshDimInWindows(void) {
    UITraitCollection* traits = BHTDimAuthorityTraits();
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            BHTRefreshDimInView(window, traits);
        }
    }
}

// The app reloads its colors as part of the switch, and views can still report
// the previous appearance at that point, so the setter hooks let them through.
// Refresh once the switch has settled; the delayed pass covers animated ones.
static void BHTScheduleDimRefresh(void) {
    static BOOL scheduled = NO;
    // Keep running after Dim is turned off: the last leg of the round trip
    // back to Dark still has the Light pass's work to undo.
    if (scheduled || (!BHTDimThemeEnabled() && !BHTDimHasRendered)) return;
    scheduled = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        BHTRefreshDimInWindows();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        scheduled = NO;
        BHTRefreshDimInWindows();
    });
}

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

// Dim is applied on the way into Dark and undone on the way into Light, so a
// setting change while the app is Dark takes a round trip through Light: the
// same path a system appearance switch takes, instead of a third one of its
// own. Forcing Light on the windows moves the traits; the palette follows
// through X's trait handler when its theme is System, and is switched here
// directly when the theme is pinned to Dark. The setting stays on through the
// Light pass so that pass restores what Dim changed; the value written at the
// end is the last one asked for, so flipping the switch again mid-trip is safe.
static BOOL BHTDimRequestedEnabled;
static BOOL BHTDimRoundTripInFlight;

void BHTDimSettingDidChange(BOOL enabled) {
    BHTDimRequestedEnabled = enabled;
    if (BHTDimRoundTripInFlight) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"enable_dim_theme"];
        return;
    }

    TAETwitterColorPaletteSettingInfo* info =
        [[objc_getClass("TAEColorSettings") sharedSettings] currentColorPalette];
    if (!info.isDark) return; // Dim is picked on the way into Dark.

    BHTDimRoundTripInFlight = YES;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"enable_dim_theme"];

    NSMutableArray<UIWindow*>* windows = [NSMutableArray array];
    NSMutableArray<NSNumber*>* styles = [NSMutableArray array];
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            [windows addObject:window];
            [styles addObject:@(window.overrideUserInterfaceStyle)];
            window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        }
    }
    [objc_getClass("T1ColorSettings") transitionToDarkMode:NO animated:NO];
    BHTScheduleDimRefresh();

    // Past the delayed refresh pass, so the Light pass has finished its work.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BHTDimRoundTripInFlight = NO;
        [NSUserDefaults.standardUserDefaults setBool:BHTDimRequestedEnabled
                                              forKey:@"enable_dim_theme"];
        [windows enumerateObjectsUsingBlock:^(UIWindow* window, NSUInteger index, BOOL* stop) {
            window.overrideUserInterfaceStyle = styles[index].integerValue;
        }];
        UIWindow* keyWindow = windows.firstObject;
        for (UIWindow* window in windows) {
            if (window.isKeyWindow) keyWindow = window;
        }
        BOOL dark = keyWindow.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        [objc_getClass("T1ColorSettings") transitionToDarkMode:dark animated:NO];
        BHTDimGeneration++;
        BHTScheduleDimRefresh();
    });
}

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
    %orig([CustomTabBarUtility usesNativeEditor] ? entries : orderedTabEntries(entries));
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
