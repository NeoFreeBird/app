#import "BHTDimPalette.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/BHTSettings.h"
#import "Headers/TAEHeaders.h"

BOOL BHTDimThemeEnabled(void) {
    return [BHTSettings boolForKey:@"enable_dim_theme"];
}

static UIColor* BHTColorWithRGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static const uint32_t kBHTDimBackgroundRGB = 0x15202B;
static const uint32_t kBHTDimElevatedBackgroundRGB = 0x192734;
static const uint32_t kBHTDimHighlightBackgroundRGB = 0x1C2836;

UIColor* BHTDimBackgroundColor(void) {
    return BHTColorWithRGB(kBHTDimBackgroundRGB);
}
UIColor* BHTDimElevatedBackgroundColor(void) {
    return BHTColorWithRGB(kBHTDimElevatedBackgroundRGB);
}
UIColor* BHTDimHighlightBackgroundColor(void) {
    return BHTColorWithRGB(kBHTDimHighlightBackgroundRGB);
}

static BOOL BHTColorMatchesRGB(CGFloat red, CGFloat green, CGFloat blue, uint32_t rgb) {
    return fabs(red - ((rgb >> 16) & 0xFF) / 255.0) < 0.002 &&
           fabs(green - ((rgb >> 8) & 0xFF) / 255.0) < 0.002 &&
           fabs(blue - (rgb & 0xFF) / 255.0) < 0.002;
}

BHTDimShadeKind BHTDimShadeOfColor(UIColor* color) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha] || alpha < 0.99) {
        return BHTDimShadeNone;
    }
    if (BHTColorMatchesRGB(red, green, blue, kBHTDimBackgroundRGB)) return BHTDimShadeBackground;
    if (BHTColorMatchesRGB(red, green, blue, kBHTDimElevatedBackgroundRGB)) return BHTDimShadeElevated;
    if (BHTColorMatchesRGB(red, green, blue, kBHTDimHighlightBackgroundRGB)) return BHTDimShadeHighlight;
    return BHTDimShadeNone;
}
UIColor* BHTDimSearchPillColor(void) {
    return BHTColorWithRGB(0x29333F);
}

static UIColor* BHTCurrentAccentColor(id<TAEColorPalette> palette) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSNumber*>* custom = [defaults arrayForKey:@"bh_color_theme_customColor"];
    if ([defaults integerForKey:@"bh_color_theme_selectedColor"] == -1 && custom.count == 4) {
        return [UIColor colorWithRed:custom[0].doubleValue
                               green:custom[1].doubleValue
                                blue:custom[2].doubleValue
                               alpha:custom[3].doubleValue];
    }
    NSInteger option = 0; // Twitter's default blue option.

    if ([defaults objectForKey:@"bh_color_theme_selectedColor"]) {
        option = [defaults integerForKey:@"bh_color_theme_selectedColor"];
    } else if ([defaults objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"]) {
        option = [defaults integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    }

    return [palette primaryColorForOption:option] ?: [UIColor systemBlueColor];
}

UIColor* _Nullable BHTDimReplacementForResolvedColor(UIColor* resolved) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if (![resolved getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return nil;
    }
    if (alpha < 0.99) {
        return nil;
    }

    CGFloat maxComponent = MAX(red, MAX(green, blue));
    CGFloat minComponent = MIN(red, MIN(green, blue));
    if (maxComponent - minComponent > 0.04) {
        return nil;
    }
    if (maxComponent > 0.22) {
        return nil;
    }

    if (maxComponent < 0.05) {
        return BHTDimBackgroundColor();
    }
    if (maxComponent < 0.14) {
        return BHTDimElevatedBackgroundColor();
    }
    return BHTDimHighlightBackgroundColor();
}

// Keeps white elements white
BOOL BHTColorIsCloseToWhite(UIColor* color) {
    if (!color) {
        return NO;
    }

    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        CGFloat white = 0;
        if (![color getWhite:&white alpha:&alpha]) {
            return NO;
        }
        red = green = blue = white;
    }
    if (alpha < 0.99) {
        return NO;
    }

    CGFloat minComponent = MIN(red, MIN(green, blue));
    return minComponent > 0.9;
}

@interface UIColor (BHTDimDynamicColorIdentifier)
- (id)tfn_dynamicColorIdentifier;
+ (UIColor*)tfn_colorWithRed:(CGFloat)red
                       green:(CGFloat)green
                        blue:(CGFloat)blue
                       alpha:(CGFloat)alpha
      dynamicColorIdentifier:(id)identifier;
@end

UIColor* BHTDimColorPreservingIdentifier(UIColor* dim, UIColor* source) {
    if (![source respondsToSelector:@selector(tfn_dynamicColorIdentifier)] ||
        ![UIColor respondsToSelector:@selector(tfn_colorWithRed:green:blue:alpha:dynamicColorIdentifier:)]) {
        return dim;
    }

    id identifier = [source tfn_dynamicColorIdentifier];
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if (!identifier || ![dim getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return dim;
    }
    UIColor* tagged = [UIColor tfn_colorWithRed:red
                                          green:green
                                           blue:blue
                                          alpha:alpha
                         dynamicColorIdentifier:identifier];
    return tagged ?: dim;
}

static UIColor* BHTDimShade(UIColor* real, UIColor* dim) {
    return BHTColorIsCloseToWhite(real) ? real : BHTDimColorPreservingIdentifier(dim, real);
}

@interface BHTDimPaletteProxy ()
@property (nonatomic, strong) id realPalette;
@end

@implementation BHTDimPaletteProxy

+ (instancetype)proxyWithPalette:(id)palette {
    BHTDimPaletteProxy* proxy = [BHTDimPaletteProxy alloc];
    proxy.realPalette = palette;
    return proxy;
}

#pragma mark - Forwarding

- (id)forwardingTargetForSelector:(SEL)selector {
    return self.realPalette;
}

- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.realPalette respondsToSelector:selector];
}

- (BOOL)conformsToProtocol:(Protocol*)protocol {
    return [self.realPalette conformsToProtocol:protocol];
}

- (BOOL)isKindOfClass:(Class)aClass {
    return [self.realPalette isKindOfClass:aClass];
}

- (BOOL)isMemberOfClass:(Class)aClass {
    return [self.realPalette isMemberOfClass:aClass];
}

- (Class)class {
    return [self.realPalette class];
}

- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector {
    return [self.realPalette methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation*)invocation {
    [invocation invokeWithTarget:self.realPalette];
}

#pragma mark - Identifier lookups

// TFNDynamicColorManager reloads a view's colors by asking the palette for an
// identifier, which is usually the getter's name. Forwarding that to the real
// palette would hand out the real Dark color for a background the getters
// below recolor, and a view not yet in a window (a prefetched cell) has no
// Dark traits for the setter hook to catch it with. Route identifiers of
// overridden getters through the override when the real palette has such a
// getter; the rest (backgroundPrimary has no getter of its own) get the same
// near-black rule the UIColor resolution hooks apply.
- (UIColor*)dynamicColorWithIdentifier:(id)identifier {
    if ([identifier isKindOfClass:NSString.class]) {
        SEL getter = NSSelectorFromString(identifier);
        if (getter && getter != _cmd && class_getInstanceMethod(object_getClass(self), getter) &&
            !class_getInstanceMethod(NSProxy.class, getter) &&
            [self.realPalette respondsToSelector:getter]) {
            return ((UIColor * (*)(id, SEL)) objc_msgSend)(self, getter);
        }
    }
    if (![self.realPalette respondsToSelector:_cmd]) {
        return nil;
    }
    UIColor* real = ((UIColor * (*)(id, SEL, id)) objc_msgSend)(self.realPalette, _cmd, identifier);
    UIColor* replacement = real ? BHTDimReplacementForResolvedColor(real) : nil;
    return replacement ? BHTDimColorPreservingIdentifier(replacement, real) : real;
}

#pragma mark - Overridden background family

- (UIColor*)backgroundColor {
    UIColor* real = [(id<TAEColorPalette>)self.realPalette backgroundColor];
    return BHTDimShade(real, BHTDimBackgroundColor());
}
- (UIColor*)backgroundPrimary {
    UIColor* real = [self.realPalette backgroundPrimary];
    return BHTDimShade(real, BHTDimBackgroundColor());
}
- (UIColor*)darkBackgroundColor {
    UIColor* real = [self.realPalette darkBackgroundColor];
    return BHTDimShade(real, BHTDimBackgroundColor());
}
- (UIColor*)cardHeaderBackgroundColor {
    UIColor* real = [self.realPalette cardHeaderBackgroundColor];
    return BHTDimShade(real, BHTDimBackgroundColor());
}
- (UIColor*)modalSheetBackgroundColor {
    UIColor* real = [self.realPalette modalSheetBackgroundColor];
    return BHTDimShade(real, BHTDimBackgroundColor());
}
- (UIColor*)messagingBackgroundColor {
    UIColor* real = [self.realPalette messagingBackgroundColor];
    return BHTDimShade(real, BHTDimBackgroundColor());
}

- (UIColor*)secondaryBackgroundColor {
    UIColor* real = [self.realPalette secondaryBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)faintBackgroundColor {
    UIColor* real = [self.realPalette faintBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)itemDarkBackgroundColor {
    UIColor* real = [self.realPalette itemDarkBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)elevatedBackgroundColor {
    UIColor* real = [self.realPalette elevatedBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)toastsBackgroundColor {
    UIColor* real = [self.realPalette toastsBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)tileBackgroundColor {
    UIColor* real = [self.realPalette tileBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)cardDetailsBackgroundColor {
    UIColor* real = [self.realPalette cardDetailsBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)premiumTiersCardBackgroundColor {
    UIColor* real = [self.realPalette premiumTiersCardBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)tweetConversationAdBackgroundColor {
    UIColor* real = [self.realPalette tweetConversationAdBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)chatTopicBackgroundColor {
    UIColor* real = [self.realPalette chatTopicBackgroundColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
- (UIColor*)dmBubbleIncomingColor {
    UIColor* real = [self.realPalette dmBubbleIncomingColor];
    return BHTDimShade(real, BHTDimElevatedBackgroundColor());
}
// Twitter's current Dark palette makes the selected capsule/tab indicator
// white. Classic Dim used the account's selected accent color instead.
- (UIColor*)tabBarItemColor {
    UIColor* real = [self.realPalette tabBarItemColor];
    return BHTColorIsCloseToWhite(real) ? BHTCurrentAccentColor(self.realPalette) : real;
}

- (UIColor*)highlightBackgroundColor {
    UIColor* real = [self.realPalette highlightBackgroundColor];
    return BHTDimShade(real, BHTDimHighlightBackgroundColor());
}
- (UIColor*)unreadBackgroundColor {
    UIColor* real = [self.realPalette unreadBackgroundColor];
    return BHTDimShade(real, BHTDimHighlightBackgroundColor());
}
- (UIColor*)highlightedStatusBackgroundColor {
    UIColor* real = [self.realPalette highlightedStatusBackgroundColor];
    return BHTDimShade(real, BHTDimHighlightBackgroundColor());
}
- (UIColor*)statusCellOverlayColor {
    UIColor* real = [self.realPalette statusCellOverlayColor];
    return BHTDimShade(real, BHTDimHighlightBackgroundColor());
}
- (UIColor*)dmInboxCellSelectionBackgroundColor {
    UIColor* real = [self.realPalette dmInboxCellSelectionBackgroundColor];
    return BHTDimShade(real, BHTDimHighlightBackgroundColor());
}

@end
