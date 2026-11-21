#import "Launch.h"

UIColor* twitterColor(void) {
    static UIColor* color;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        color = [UIColor colorWithRed:29.0 / 255.0
                                green:155.0 / 255.0
                                 blue:240.0 / 255.0
                                alpha:1.0];
    });
    return color;
}
