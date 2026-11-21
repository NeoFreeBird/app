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

void BHTApplyScrollEdgeBlur(XDSBlur* blur) {
    if (!BHTIsInsideScrollEdgeTreatment(blur)) return;
    Ivar tintField = class_getInstanceVariable(object_getClass(blur), "tintView");
    UIView* tintView = tintField ? object_getIvar(blur, tintField) : nil;
    if (![tintView isKindOfClass:UIView.class]) return;
    UIColor* dim = BHTDimScrollEdgeColor(tintView.backgroundColor, blur.traitCollection);
    if (dim) tintView.backgroundColor = dim;
}

NSArray* BHTDimScrollEdgeColors(NSArray* colors, UITraitCollection* traits) {
    NSMutableArray* mapped = [NSMutableArray arrayWithCapacity:colors.count];
    BOOL changed = NO;
    for (id entry in colors) {
        UIColor* dim = BHTDimScrollEdgeColor([UIColor colorWithCGColor:(__bridge CGColorRef)entry], traits);
        [mapped addObject:dim ? (__bridge id)dim.CGColor : entry];
        changed |= dim != nil;
    }
    return changed ? mapped : colors;
}

void BHTApplyScrollEdgeFade(UIView* fade) {
    if (!BHTIsInsideScrollEdgeTreatment(fade) || !BHTDimThemeEnabled() ||
        fade.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) return;

    Ivar gradientField = class_getInstanceVariable(object_getClass(fade), "gradientLayer");
    CAGradientLayer* gradient = gradientField ? object_getIvar(fade, gradientField) : nil;
    if (![gradient isKindOfClass:CAGradientLayer.class]) return;

    NSArray* colors = gradient.colors;
    if (!colors.count) return;
    NSArray* mapped = BHTDimScrollEdgeColors(colors, fade.traitCollection);
    if (mapped != colors) gradient.colors = mapped;
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

UIColor* BHTDimNormalizedViewBackground(UIView* view, UIColor* color) {
    if (!view || !color || !BHTDimThemeEnabled() ||
        view.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return color;
    }

    if (BHTIsScrollEdgeBlurTintView(view)) {
        UIColor* dimTint = BHTDimScrollEdgeColor(color, view.traitCollection);
        if (dimTint) return dimTint;
    }

    UIColor* resolved = [color resolvedColorWithTraitCollection:view.traitCollection];
    UIColor* replacement = BHTDimReplacementForResolvedColor(resolved);
    if (replacement) {
        return replacement;
    }

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

void BHTApplyDimToVideoControls(UIView* controlsView) {
    if (!BHTDimThemeEnabled() || !controlsView ||
        controlsView.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return;
    }

    controlsView.superview.backgroundColor = BHTDimElevatedBackgroundColor();
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

void BHTApplyDimSearchPill(UISearchBar* searchBar) {
    if (!BHTDimThemeEnabled() ||
        searchBar.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        return;
    }
    [searchBar setSearchFieldBackgroundImage:BHTDimSearchPillImage()
                                    forState:UIControlStateNormal];
}

BOOL BHTIsExploreSearchBackgroundView(UIView* view) {
    return ThemeAncestorOfClass(view, objc_getClass("TFNSearchBar")) != nil;
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
        return (id<TAEColorPalette>)[BHTDimPaletteProxy proxyWithPalette:realPalette];
    }
    return realPalette;
}

UIColor* BHTThemeSystemBackground(UIColor* original, UIColor* dim) {
    if (!BHTDimThemeEnabled()) return original;
    return [UIColor colorWithDynamicProvider:^UIColor*(UITraitCollection* traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dim : original;
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
