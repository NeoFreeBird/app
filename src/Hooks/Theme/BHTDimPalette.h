#import <UIKit/UIKit.h>

BOOL BHTDimThemeEnabled(void);

// 4 dim shades
UIColor* BHTDimBackgroundColor(void);
UIColor* BHTDimElevatedBackgroundColor(void);
UIColor* BHTDimHighlightBackgroundColor(void);
UIColor* BHTDimSearchPillColor(void);

UIColor* _Nullable BHTDimReplacementForResolvedColor(UIColor* resolved);
BOOL BHTColorIsCloseToWhite(UIColor* _Nullable color);

@interface BHTDimPaletteProxy : NSProxy
+ (instancetype)proxyWithPalette:(id)palette;
@end
