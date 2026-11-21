#import "BHTDimPalette.h"
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

UIColor* BHTDimBackgroundColor(void) {
    return BHTColorWithRGB(0x15202B);
}
UIColor* BHTDimElevatedBackgroundColor(void) {
    return BHTColorWithRGB(0x192734);
}
UIColor* BHTDimHighlightBackgroundColor(void) {
    return BHTColorWithRGB(0x1C2836);
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

#pragma mark - Overridden background family

- (UIColor*)backgroundColor {
    UIColor* real = [(id<TAEColorPalette>)self.realPalette backgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimBackgroundColor();
}
- (UIColor*)backgroundPrimary {
    UIColor* real = [self.realPalette backgroundPrimary];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimBackgroundColor();
}
- (UIColor*)darkBackgroundColor {
    UIColor* real = [self.realPalette darkBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimBackgroundColor();
}
- (UIColor*)cardHeaderBackgroundColor {
    UIColor* real = [self.realPalette cardHeaderBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimBackgroundColor();
}
- (UIColor*)modalSheetBackgroundColor {
    UIColor* real = [self.realPalette modalSheetBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimBackgroundColor();
}
- (UIColor*)messagingBackgroundColor {
    UIColor* real = [self.realPalette messagingBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimBackgroundColor();
}

- (UIColor*)secondaryBackgroundColor {
    UIColor* real = [self.realPalette secondaryBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)faintBackgroundColor {
    UIColor* real = [self.realPalette faintBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)itemDarkBackgroundColor {
    UIColor* real = [self.realPalette itemDarkBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)elevatedBackgroundColor {
    UIColor* real = [self.realPalette elevatedBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)toastsBackgroundColor {
    UIColor* real = [self.realPalette toastsBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)tileBackgroundColor {
    UIColor* real = [self.realPalette tileBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)cardDetailsBackgroundColor {
    UIColor* real = [self.realPalette cardDetailsBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)premiumTiersCardBackgroundColor {
    UIColor* real = [self.realPalette premiumTiersCardBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)tweetConversationAdBackgroundColor {
    UIColor* real = [self.realPalette tweetConversationAdBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)chatTopicBackgroundColor {
    UIColor* real = [self.realPalette chatTopicBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
- (UIColor*)dmBubbleIncomingColor {
    UIColor* real = [self.realPalette dmBubbleIncomingColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimElevatedBackgroundColor();
}
// Twitter's current Dark palette makes the selected capsule/tab indicator
// white. Classic Dim used the account's selected accent color instead.
- (UIColor*)tabBarItemColor {
    UIColor* real = [self.realPalette tabBarItemColor];
    return BHTColorIsCloseToWhite(real) ? BHTCurrentAccentColor(self.realPalette) : real;
}

- (UIColor*)highlightBackgroundColor {
    UIColor* real = [self.realPalette highlightBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimHighlightBackgroundColor();
}
- (UIColor*)unreadBackgroundColor {
    UIColor* real = [self.realPalette unreadBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimHighlightBackgroundColor();
}
- (UIColor*)highlightedStatusBackgroundColor {
    UIColor* real = [self.realPalette highlightedStatusBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimHighlightBackgroundColor();
}
- (UIColor*)statusCellOverlayColor {
    UIColor* real = [self.realPalette statusCellOverlayColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimHighlightBackgroundColor();
}
- (UIColor*)dmInboxCellSelectionBackgroundColor {
    UIColor* real = [self.realPalette dmInboxCellSelectionBackgroundColor];
    return BHTColorIsCloseToWhite(real) ? real : BHTDimHighlightBackgroundColor();
}

@end
