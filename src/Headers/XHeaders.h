#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface XDSButtonContentElement : NSObject
+ (id)labelWithText:(id)text font:(id)font color:(id)color;
@end

// Builds and caches the design system's fonts.
@interface XFontCatalog : NSObject
+ (UIFont*)fontForToken:(NSInteger)token;
+ (UIFont*)customFontOfSize:(CGFloat)size weight:(NSInteger)weight scalesWithDynamicType:(BOOL)scales;
+ (UIFont*)contentFontWithOffset:(CGFloat)offset weight:(NSInteger)weight;
+ (UIFont*)tabularDigitsFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
+ (void)resetCachedFonts;
@end

@interface XNAVNavigationController: UINavigationController
@end

@interface XTabbedAppNavigationSplitViewControllerFactory : NSObject
@end

@interface XDSButton : UIControl
@end

@interface  _TtC13QuickComposer21QuickComposerSlotView : UIView
@end
