//
//  BHTHelpers.h
//  NeoFreeBird
//
//  Created by BandarHelal
//

#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import "TAEHeaders.h"

@interface NSParagraphStyle ()
+ (NSWritingDirection)_defaultWritingDirection;
@end

@interface SFSafariViewController ()
- (NSURL*)initialURL;
@end

static void changeTwitterColor(NSInteger colorID) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    TAEColorSettings* colorSettings =
        [objc_getClass("TAEColorSettings") sharedSettings];

    [defaults setObject:@(colorID)
                 forKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    [colorSettings setPrimaryColorOption:colorID];
}
static UIImage* imageFromView(UIView* view) {
    TAEColorSettings* colorSettings =
        [objc_getClass("TAEColorSettings") sharedSettings];
    bool opaque = [colorSettings.currentColorPalette isDark] ? true : false;
    UIGraphicsBeginImageContextWithOptions(view.frame.size, opaque, 0.0);
    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:false];
    UIImage* img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return img;
}

static BOOL isDeviceLanguageRTL() {
    return [NSParagraphStyle _defaultWritingDirection] ==
           NSWritingDirectionRightToLeft;
}
static BOOL is_iPad() {
    if ([(NSString*)[UIDevice currentDevice].model hasPrefix:@"iPad"]) {
        return YES;
    }
    return NO;
}

static BOOL is_Mac(void) {
    NSProcessInfo* info = NSProcessInfo.processInfo;
    return info.isiOSAppOnMac || info.isMacCatalystApp;
}

// https://github.com/julioverne/MImport/blob/0275405812ff41ed2ca56e98f495fd05c38f41f2/mimporthook/MImport.xm#L59
static UIViewController* _Nullable _topMostController(
    UIViewController* _Nonnull cont) {
    UIViewController* topController = cont;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    if ([topController isKindOfClass:[UINavigationController class]]) {
        UIViewController* visible =
            ((UINavigationController*)topController).visibleViewController;
        if (visible) {
            topController = visible;
        }
    }
    return (topController != cont ? topController : nil);
}
static UIViewController* _Nonnull topMostController() {
    UIViewController* topController =
        [UIApplication sharedApplication].keyWindow.rootViewController;
    UIViewController* next = nil;
    while ((next = _topMostController(topController)) != nil) {
        topController = next;
    }
    return topController;
}

@interface UIImageView (TwitterLogo)
- (id)initWithImage:(UIImage*)image;
- (void)setImage:(UIImage*)image;
@end

@interface TweetSourceHelper : NSObject
+ (void)fetchSourceForTweetID:(NSString*)tweetID;
@end

// Defined in Hooks/BHTHookHelpers.m
extern UIColor* CurrentAccentColor(void);

extern void BHTMarkAccentTintedIcon(UIView* view, BOOL tinted);
extern void BHTReapplyAccentTintedIcons(void);
