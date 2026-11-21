//
//  CustomTabBarUtility.m
//  NeoFreeBird
//
//  Created by Bandar Alruwaili on 10/12/2023.
//

#import "CustomTabBarUtility.h"
#import <objc/message.h>
#import "Headers/T1Headers.h"

@protocol BHTNativeTabCustomizationInitializing <NSObject>
- (instancetype)initWithAccount:(id)account scribeContext:(id)context;
@end

@implementation CustomTabBarUtility

#pragma mark - Editor routing

+ (BOOL)usesNativeEditor {
    Class editorClass = NSClassFromString(@"T1TabCustomizationViewController");
    return [editorClass isSubclassOfClass:[UIViewController class]] &&
           [editorClass instancesRespondToSelector:@selector(initWithAccount:scribeContext:)];
}

+ (UIViewController*)editorForAccount:(id)account {
    Class editorClass = NSClassFromString(@"T1TabCustomizationViewController");
    Class contextClass = NSClassFromString(@"TFSTwitterScribeContext");
    SEL contextSelector = @selector(scribeContextWithPage:);
    if (![self usesNativeEditor] || ![contextClass respondsToSelector:contextSelector]) {
        return nil;
    }

    if (!account) {
        id host = [NSClassFromString(@"T1HostViewController") sharedHostViewController];
        account = [host currentAccount];
    }
    if (!account) {
        return nil;
    }

    id context = ((id (*)(id, SEL, id))objc_msgSend)(
        contextClass, contextSelector, @"settings");
    if (!context) {
        return nil;
    }

    return (UIViewController*)[(id<BHTNativeTabCustomizationInitializing>)[editorClass alloc]
        initWithAccount:account
          scribeContext:context];
}

@end
