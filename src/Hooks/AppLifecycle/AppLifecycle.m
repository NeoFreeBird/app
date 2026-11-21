#import "AppLifecycle.h"

// The launch animation reveals the app through a growing X-shaped mask
// (revealMaskLayer / holePathInView); this keeps only the logo zoom

void stripLaunchRevealMask(UIView* view) {
    view.layer.mask = nil;
    for (UIView* sub in view.subviews) {
        sub.layer.mask = nil;
    }
}

UIWindow* activeKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (w.isKeyWindow)
                        return w;
                }
                for (UIWindow* w in ws.windows) {
                    if (!w.hidden)
                        return w;
                }
            }
        }
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow)
            return w;
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (!w.hidden)
            return w;
    }
    return nil;
}

void showPadlockOverlay(void) {
    if (padlockController.view.window)
        return;

    UIWindow* window = activeKeyWindow();
    if (!window)
        return;

    if (!padlockController) {
        padlockController = [[AuthViewController alloc] init];
        padlockController.completion = ^(BOOL authenticated) {
            if (authenticated) {
                padlockAuthenticated = YES;
                [padlockController.view removeFromSuperview];
                padlockController = nil;
            }
        };
    }

    UIView* overlay = padlockController.view;
    overlay.frame = window.bounds;
    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:overlay];
}

void removePadlockOverlay(void) {
    [padlockController pauseAuthentication];
    [padlockController.view removeFromSuperview];
    padlockController = nil;
}

NSString* testAlertVersion(void) {
    NSDictionary* info = NSBundle.mainBundle.infoDictionary;
    return [NSString stringWithFormat:@"%@/%@/%@",
                                      info[@"CFBundleShortVersionString"] ?: @"",
                                      info[@"CFBundleVersion"] ?: @"",
                                      @NFB_VERSION_STRING];
}

void scheduleTestAlertIfNeeded(void) {
    if (testAlertScheduled ||
        [[NSUserDefaults.standardUserDefaults stringForKey:testAlertVersionKey]
            isEqualToString:testAlertVersion()]) return;

    testAlertScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       testAlertScheduled = NO;
                       if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive)
                           return;

                       UIWindow* window = activeKeyWindow();
                       UIViewController* root = window.rootViewController;
                       UIViewController* host = topMostController();
                       if (!host || !root.view.window ||
                           ([BHTSettings boolForKey:@"padlock"] && !padlockAuthenticated) ||
                           [host isKindOfClass:UIAlertController.class] ||
                           [host isKindOfClass:AuthViewController.class]) {
                           scheduleTestAlertIfNeeded();
                           return;
                       }

                       NSString* version = testAlertVersion();
                       if ([[NSUserDefaults.standardUserDefaults stringForKey:testAlertVersionKey]
                               isEqualToString:version]) return;

                       UIAlertController* alert = [UIAlertController
                           alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"GITHUB_DOWNLOAD_WARNING_TITLE"]
                                            message:[[BHTBundle sharedBundle] localizedStringForKey:@"GITHUB_DOWNLOAD_WARNING_MESSAGE"]
                                     preferredStyle:UIAlertControllerStyleAlert];
                       [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                                 style:UIAlertActionStyleDefault
                                                               handler:nil]];
                       [topMostController() presentViewController:alert
                                                         animated:YES
                                                       completion:^{
                                                           [NSUserDefaults.standardUserDefaults setObject:version
                                                                                                   forKey:testAlertVersionKey];
                                                       }];
                   });
}
