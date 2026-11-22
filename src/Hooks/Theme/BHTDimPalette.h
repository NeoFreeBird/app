#import <UIKit/UIKit.h>

BOOL BHTDimThemeEnabled(void);

// 4 dim shades
UIColor* BHTDimBackgroundColor(void);
UIColor* BHTDimElevatedBackgroundColor(void);
UIColor* BHTDimHighlightBackgroundColor(void);
UIColor* BHTDimSearchPillColor(void);

// Which Dim shade an opaque color is, if any
typedef NS_ENUM(NSInteger, BHTDimShadeKind) {
    BHTDimShadeNone,
    BHTDimShadeBackground,
    BHTDimShadeElevated,
    BHTDimShadeHighlight,
};

BHTDimShadeKind BHTDimShadeOfColor(UIColor* _Nullable color);

UIColor* _Nullable BHTDimReplacementForResolvedColor(UIColor* resolved);
BOOL BHTColorIsCloseToWhite(UIColor* _Nullable color);

// Keeps source's dynamic color identifier, so X can reload the color from the
// next palette on an appearance change
UIColor* BHTDimColorPreservingIdentifier(UIColor* dim, UIColor* _Nullable source);

@interface BHTDimPaletteProxy : NSProxy
+ (instancetype)proxyWithPalette:(id)palette;
@end
