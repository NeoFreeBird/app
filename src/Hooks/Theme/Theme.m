#import "Theme.h"
#import "../HookHelpers.h"

@interface UIColor (BHTDynamicColorIdentifier)
- (id)tfn_dynamicColorIdentifier;
@end

// MARK: - Custom accent color

NSNumber* BHTSelectedThemeColor(void) {
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

NSInteger BHTNativeThemeOption(NSInteger option) {
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

    return [custom colorWithAlphaComponent:MIN(1.0, custom.CGColor ? CGColorGetAlpha(custom.CGColor) * a : a)];
}

// Every apply path (launch re-apply, trait changes, both settings pickers)
// funnels through this setter, so coercing here keeps the custom color pinned.

void applySelectedThemeColor(void) {
    NSNumber* selectedColor = BHTSelectedThemeColor();
    if (selectedColor) {
        [[objc_getClass("TAEColorSettings") sharedSettings]
            setPrimaryColorOption:BHTNativeThemeOption(selectedColor.integerValue)];
    }
}

// The native palette supplies most accent-colored controls via primaryColor.
// Keep the six preset getters intact so their picker swatches stay accurate.

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
        objc_setAssociatedObject(info, &BHTLastNativeAccentKey, @{@"option": @(option),
                                                                  @"color": color},
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

// Attributed strings and view setters resolve saved dynamic color identifiers
// through this manager, bypassing the named palette loader above.

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

static UIView* ThemeAncestorOfClass(UIView* view, Class ancestorClass) {
    for (UIView* ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:ancestorClass]) return ancestor;
    }
    return nil;
}

static BOOL BHTDimGlassIsInContainer(UIView* glass, NSString* className) {
    return ThemeAncestorOfClass(glass, NSClassFromString(className)) != nil;
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

void BHTUpdateDimGlass(UIView* glass) {
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
                                         ? (UIVisualEffectView*)parent.superview
                                         : nil;
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

BOOL BHTIsInsideScrollEdgeTreatment(UIView* view) {
    return ThemeAncestorOfClass(view, NSClassFromString(@"_TtC13XDesignSystem19ScrollEdgeTreatment")) != nil;
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

void BHTApplyScrollEdgeBlur(XDSBlur* blur) {
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
// Dim hooks, which turn opaque black into a navy this filter rejects.
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

static NSArray* BHTDimFadeGradientColors(NSArray* colors, UITraitCollection* traits) {
    NSMutableArray* mapped = [NSMutableArray arrayWithCapacity:colors.count];
    BOOL changed = NO;
    for (id entry in colors) {
        UIColor* dim = BHTDimFadeGradientColor((__bridge CGColorRef)entry, traits);
        [mapped addObject:dim ? (__bridge id)dim.CGColor : entry];
        changed |= dim != nil;
    }
    return changed ? mapped : colors;
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

void BHTApplyScrollEdgeFade(UIView* fade) {
    if (!BHTIsDimFadeView(fade) || !BHTDimThemeEnabled() ||
        fade.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) return;

    Ivar gradientField = class_getInstanceVariable(object_getClass(fade), "gradientLayer");
    CAGradientLayer* gradient = gradientField ? object_getIvar(fade, gradientField)
                                              : (CAGradientLayer*)fade.layer;
    if (![gradient isKindOfClass:CAGradientLayer.class]) return;

    NSArray* colors = gradient.colors;
    if (!colors.count) return;
    NSArray* mapped = BHTDimFadeGradientColors(colors, fade.traitCollection);
    if (mapped != colors) gradient.colors = mapped;
}

NSArray* BHTThemeGradientColors(CAGradientLayer* layer, NSArray* colors) {
    // TFNGradientView is backed by the gradient layer itself.
    UIView* owner = [(id)layer.delegate isKindOfClass:NSClassFromString(@"TFNGradientView")]
                        ? (UIView*)layer.delegate
                        : (UIView*)layer.superlayer.delegate;
    if (![owner isKindOfClass:UIView.class] || !BHTIsDimFadeView(owner) ||
        !BHTDimThemeEnabled() ||
        owner.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return colors;
    }
    return BHTDimFadeGradientColors(colors, owner.traitCollection);
}

void BHTApplyDimScrollEdgeChildren(UIView* treatment) {
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

// Set once the Dim palette has been handed out, so the restore paths know
// there may be Dim colors to undo even after the setting is turned off.
static BOOL BHTDimHasRendered;
static char BHTDimProxyKey;

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
        // A palette color from before the toggle: the setter hook then
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

void BHTRefreshDimBackground(UIView* view) {
    BHTRefreshDimBackgroundAs(view, BHTDimAuthorityTraits() ?: view.traitCollection);
}

// X sometimes assigns backgroundPrimary (or a literal black color) to a view
// after the palette has already been resolved, which the palette proxy and the
// UIColor resolution hooks never see.
UIColor* BHTThemeViewBackground(UIView* view, UIColor* color) {
    // Nothing to apply or undo until Dim has rendered in this process.
    if ((!BHTDimThemeEnabled() && !BHTDimHasRendered) || BHTDimLeavesBackgroundAlone(view)) {
        return color;
    }
    UIColor* normalized = BHTDimNormalizedBackground(view, color, view.traitCollection);
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
            BHTSaveDimOriginalBackground(view, color);
        }
    } else if (objc_getAssociatedObject(view, &BHTDimOriginalBackgroundKey) &&
               !BHTColorIsFlatDimShade(color)) {
        // The app assigned a new color of its own, which supersedes the saved one.
        objc_setAssociatedObject(view, &BHTDimOriginalBackgroundKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return normalized;
}

static char BHTDimHidSolidColorViewKey;

// Dim only recolors Dark, so these views are hidden in Dark alone. The flag
// records which ones Dim hid, so views the app hid itself stay hidden in Light.
void BHTApplyDimSolidColorView(UIView* view) {
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

UIImage* BHTDimSearchPillImage(void) {
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

void BHTApplyDimSearchPill(UISearchBar* searchBar) {
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

BOOL BHTIsExploreSearchBackgroundView(UIView* view) {
    return ThemeAncestorOfClass(view, objc_getClass("TFNSearchBar")) != nil;
}

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
                        ? [color tfn_dynamicColorIdentifier]
                        : nil;
    UIColor* reloaded = identifier && [palette respondsToSelector:@selector(dynamicColorWithIdentifier:)]
                            ? [palette dynamicColorWithIdentifier:identifier]
                            : nil;
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
void BHTApplyDisabledBarButtonTextColor(UIViewController* controller) {
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

static char BHTSegmentedTabBarAppearanceKey;

// The tab bar's style holds its title colors from when it was built, so they
// have to be fetched again from the new palette after an appearance change.
void BHTRefreshSegmentedTabBarColors(_TtC10TFNUISwift25LegacySegmentedTabBarView* tabBar) {
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

void BHTApplyDimBarBackground(UIView* bar) {
    if (!BHTDimThemeEnabled() || NFBLiquidGlassEnabled() ||
        bar.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return;
    }
    UIColor* original = bar.backgroundColor;
    if (BHTColorIsDimShade(original)) return;
    bar.backgroundColor = BHTDimBackgroundColor();
    BHTSaveDimOriginalBackground(bar, original);
}

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
void BHTScheduleDimRefresh(void) {
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
                       [windows enumerateObjectsUsingBlock:^(UIWindow* window, NSUInteger index,
                                                             BOOL* stop) {
                           window.overrideUserInterfaceStyle = styles[index].integerValue;
                       }];
                       UIWindow* keyWindow = windows.firstObject;
                       for (UIWindow* window in windows) {
                           if (window.isKeyWindow) keyWindow = window;
                       }
                       BOOL dark = keyWindow.traitCollection.userInterfaceStyle ==
                                   UIUserInterfaceStyleDark;
                       [objc_getClass("T1ColorSettings") transitionToDarkMode:dark animated:NO];
                       BHTDimGeneration++;
                       BHTScheduleDimRefresh();
                   });
}

// MARK: - Tab bar icon and label theming

static char BHTGlassTabOriginalTintKey;
static char BHTGlassTabLabelKey;
static char BHTGlassTabOverlayKey;

static UILabel* BHTCreateTabLabel(void) {
    UILabel* label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.isAccessibilityElement = NO;
    label.userInteractionEnabled = NO;
    return label;
}

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

void BHTLayoutGlassTabItem(UIView* item) {
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

void BHTApplyGlassTabLabels(UIView* bar) {
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

    NSMutableSet<UIView*>* activeLabels = [NSMutableSet new];
    for (NSUInteger index = 0; index < items.count; index++) {
        UIView* item = items[index];
        UILabel* label = objc_getAssociatedObject(item, &BHTGlassTabLabelKey);
        NSString* title = enabled ? BHTGlassTabItemTitle(item, bar) : nil;
        if (!label && title.length) {
            label = BHTCreateTabLabel();
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

void BHTApplyGlassTabAccent(UIView* item) {
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

static char BHTLegacyTabLabelKey;
static char BHTLegacyTabGlyphShiftKey;

UIColor* BHTTabItemColor(BOOL selected) {
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
        label = BHTCreateTabLabel();
        objc_setAssociatedObject(tabView, &BHTLegacyTabLabelKey, label,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    label.text = tabView.title;
    label.textColor = BHTTabItemColor(tabView.selected);
    label.frame = CGRectMake(2.0, CGRectGetHeight(tabView.bounds) - 13.0,
                             MAX(0.0, CGRectGetWidth(tabView.bounds) - 4.0), 11.0);
    if (label.superview != tabView) [tabView addSubview:label];
    [tabView bringSubviewToFront:label];
}

// MARK: - Top bar logo theming

// MARK: - iPad sidebar logo theming

void BHTApplySidebarIconTheme(UIViewController* sidebar) {
    Ivar iconViewIvar =
        class_getInstanceVariable(NSClassFromString(@"T1AppSplitSideBarViewController"), "_iconView");
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

#pragma mark - Hook entry points

UIColor* BHTThemePrimaryColor(id palette, UIColor* native) {
    objc_setAssociatedObject(palette, &BHTNativePrimaryColorKey, native,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return selectedCustomThemeColor() ?: native;
}

UIColor* BHTThemeLoadedColor(id loader, NSString* name, UIColor* color) {
    if (BHTMappingLoadedColor || !selectedCustomThemeColor() ||
        ![name isKindOfClass:NSString.class] ||
        [name isEqualToString:@"primaryColor"] ||
        [name hasPrefix:@"primaryColorOption"]) return color;

    BHTMappingLoadedColor = YES;
    Ivar paletteField = class_getInstanceVariable(object_getClass(loader), "_palette");
    id palette = paletteField ? object_getIvar(loader, paletteField) : nil;
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

UIColor* BHTThemeDynamicColor(UIColor* color, UIColor* resolved) {
    if (BHTMappingDynamicColor || !selectedCustomThemeColor()) return resolved;
    id identifier = [color respondsToSelector:@selector(tfn_dynamicColorIdentifier)]
                        ? [color tfn_dynamicColorIdentifier]
                        : nil;
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

id<TAEColorPalette> BHTThemeColorPalette(id info, id<TAEColorPalette> realPalette, BOOL isDark) {
    if (selectedCustomThemeColor()) {
        UIColor* native = objc_getAssociatedObject(realPalette, &BHTNativePrimaryColorKey);
        if (!native && [(id)realPalette respondsToSelector:@selector(primaryColor)]) {
            ((id (*)(id, SEL))objc_msgSend)(realPalette, @selector(primaryColor));
            native = objc_getAssociatedObject(realPalette, &BHTNativePrimaryColorKey);
        }
        objc_setAssociatedObject(info, &BHTNativePrimaryColorKey, native,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (isDark && BHTDimThemeEnabled()) {
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

// Dim can be turned off while the app runs, so the provider checks the setting
// on every resolve rather than only when the color was created.
UIColor* BHTThemeSystemBackground(UIColor* original, UIColor* dim) {
    if (!BHTDimThemeEnabled()) return original;
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return BHTDimThemeEnabled() && traits.userInterfaceStyle == UIUserInterfaceStyleDark
                   ? dim
                   : original;
    }];
}

UIColor* BHTThemeResolvedBackground(UIColor* original, UITraitCollection* traits) {
    if (!BHTDimThemeEnabled() || traits.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return original;
    }
    return BHTDimReplacementForResolvedColor(original) ?: original;
}

void BHTUpdateLegacyTabLabelColor(T1TabView* tabView, BOOL selected) {
    UILabel* label = objc_getAssociatedObject(tabView, &BHTLegacyTabLabelKey);
    label.textColor = BHTTabItemColor(selected);
}

UIView* BHTPrepareLegacyTabLayout(T1TabView* tabView) {
    UIView* glyph = tabView.transformContainer ?: tabView.imageView;
    if ([objc_getAssociatedObject(glyph, &BHTLegacyTabGlyphShiftKey) boolValue]) {
        glyph.center = CGPointMake(glyph.center.x, glyph.center.y + 5.0);
        objc_setAssociatedObject(glyph, &BHTLegacyTabGlyphShiftKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return glyph;
}

void BHTFinishLegacyTabLayout(T1TabView* tabView, UIView* glyph) {
    BHTLayoutLegacyTabLabel(tabView);
    if ([BHTSettings boolForKey:@"restore_tab_labels"] && tabView.title.length &&
        CGRectGetHeight(tabView.bounds) >= 34.0 && glyph) {
        glyph.center = CGPointMake(glyph.center.x, glyph.center.y - 5.0);
        objc_setAssociatedObject(glyph, &BHTLegacyTabGlyphShiftKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
