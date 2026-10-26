//
//  BHTDimPalette.m
//  NeoFreeBird
//
//  Created by orionblur
//

#import "ThemeColor/BHTDimPalette.h"
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

// Classic Twitter Dim palette: a navy background, a slightly lighter navy for
// anything elevated/secondary, and a lighter shade still for pressed/selected
// states. Text, links, and accent colors are left alone -- Dim only ever
// changed the background family, never the foreground. Exposed (not static)
// so Theme.x's UIColor hook can reuse the same three shades.
UIColor* BHTDimBackgroundColor(void) {
    return BHTColorWithRGB(0x15202B);
}
UIColor* BHTDimElevatedBackgroundColor(void) {
    return BHTColorWithRGB(0x192734);
}
UIColor* BHTDimHighlightBackgroundColor(void) {
    return BHTColorWithRGB(0x1C2836);
}

// The legacy Dim search field used its own neutral shade rather than any of
// the three general-purpose background colors above.
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

// UIDynamicSystemColor/UIDynamicCatalogColor (the private classes backing
// UIKit's system colors and asset-catalog +colorNamed: colors) never go
// through TAEColorPalette or the named UIColor class methods, so anything
// they draw has to be caught after the fact, once resolved to a flat RGBA
// color. Since we don't know which named color it was, only remap colors
// that plausibly *are* background chrome: fully opaque and achromatic (no
// real hue -- rules out accent colors, media, everything colorful), sitting
// in the narrow near-black band Apple actually uses for dark background
// tones (systemBackground ~0.0, secondarySystemBackground ~0.11,
// tertiarySystemBackground ~0.17). Brighter grays are left untouched, since
// those are far more likely to be label/fill/separator colors that need to
// stay legible rather than become part of the background.
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

// Self-contained white check -- deliberately not UIColor's private
// safari_isCloseToWhite category, which didn't behave reliably here. Grayscale
// colors (e.g. +whiteColor, which resolves via -getWhite:alpha: rather than
// -getRed:green:blue:alpha:) are handled explicitly rather than falling
// through to "not white".
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

// Anything we don't explicitly override below (text, links, accents,
// dividers, primaryColorForOption:, ...) goes straight through to the real
// palette untouched via this fast path.
- (id)forwardingTargetForSelector:(SEL)selector {
    return self.realPalette;
}

// NSProxy's -respondsToSelector:/-conformsToProtocol:/-isKindOfClass: are not
// implemented in terms of -forwardingTargetForSelector: -- they're "real"
// methods on NSProxy itself, so they never reach our overrides above and
// instead fall into the slow invocation-based forwarding path below. Swift's
// dynamic protocol casts (`as? TAEColorPalette`) call -conformsToProtocol:
// directly, so without an explicit override here the proxy answers NO/crashes
// instead of transparently reporting whatever the real palette would.
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

// Slow-path forwarding: a safety net for anything the fast path above
// doesn't catch (e.g. selectors NSProxy itself implements).
- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector {
    return [self.realPalette methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation*)invocation {
    [invocation invokeWithTarget:self.realPalette];
}

#pragma mark - Overridden background family

- (UIColor*)backgroundColor {
    UIColor* real = [self.realPalette backgroundColor];
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
