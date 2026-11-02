//
//  AppLifecycle.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Padlock helpers

// Authentication is intentionally in memory so every app launch starts locked.
static BOOL padlockAuthenticated = NO;
static AuthViewController* padlockController = nil;

static UIWindow* activeKeyWindow(void) {
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

static void showPadlockOverlay(void) {
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

static void removePadlockOverlay(void) {
    [padlockController pauseAuthentication];
    [padlockController.view removeFromSuperview];
    padlockController = nil;
}

static NSString* testAlertVersion(void) {
    NSDictionary* info = NSBundle.mainBundle.infoDictionary;
    return [NSString stringWithFormat:@"%@/%@/%@",
                                      info[@"CFBundleShortVersionString"] ?: @"",
                                      info[@"CFBundleVersion"] ?: @"",
                                      @NFB_VERSION_STRING];
}

static BOOL testAlertScheduled = NO;
static NSString* const testAlertVersionKey = @"nfb_test_alert_last_seen_version";

static void scheduleTestAlertIfNeeded(void) {
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
        [topMostController() presentViewController:alert animated:YES completion:^{
            [NSUserDefaults.standardUserDefaults setObject:version
                                                    forKey:testAlertVersionKey];
        }];
    });
}

// MARK: - App Delegate hooks

%hook T1AppDelegate

- (_Bool)application:(__unsafe_unretained UIApplication*)application
    didFinishLaunchingWithOptions:(__unsafe_unretained id)arg2 {
    _Bool orig = %orig;

    [BHTManager cleanCache];
    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        applySelectedThemeColor();
    });

    return orig;
}

- (void)applicationDidBecomeActive:(__unsafe_unretained id)arg1 {
    %orig;

    applySelectedThemeColor();
    prewarmWebCookiesIfNeeded();

    if ([BHTSettings boolForKey:@"padlock"]) {
        if (padlockAuthenticated) {
            removePadlockOverlay();
        } else {
            BOOL alreadyVisible = padlockController.view.window != nil;
            showPadlockOverlay();
            if (alreadyVisible)
                [padlockController resumeAuthenticationIfNeeded];
            else {
                AuthViewController* controller = padlockController;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (padlockController == controller)
                        [controller retryAuthentication];
                });
            }
        }
    } else {
        removePadlockOverlay();
    }

    scheduleTestAlertIfNeeded();
}

- (void)applicationWillResignActive:(__unsafe_unretained id)arg1 {
    %orig;

    if ([BHTSettings boolForKey:@"padlock"]) {
        // A visible lock view already covers the app during Face ID's own
        // temporary inactive transition. Only add one when leaving unlocked.
        if (padlockAuthenticated || !padlockController.view.window) {
            showPadlockOverlay();
            [padlockController pauseAuthentication];
        }
        padlockAuthenticated = NO;
    }

    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }
}

- (void)applicationDidEnterBackground:(__unsafe_unretained id)arg1 {
    %orig;

    if ([BHTSettings boolForKey:@"padlock"])
        [padlockController pauseAuthentication];
}

%end

%hook TFNTwitterAccount
- (_Bool)shouldJumpBackToHomeWithActiveTimeStamp:(double)active
                                inactiveTimeStamp:(double)inactive {
    if ([BHTSettings boolForKey:@"no_focus_lost"])
        return NO;
    return %orig(active, inactive);
}
%end

// MARK: - Restore Launch Animation

// The launch animation reveals the app through a growing X-shaped mask
// (revealMaskLayer / holePathInView); detach it so the logo zoom is kept but
// the splash simply fades out.

static void stripLaunchRevealMask(UIView* view) {
    // The X-shaped hole lives on the container subview's layer.mask; the top
    // view itself is unmasked, but clear it too for safety.
    view.layer.mask = nil;
    for (UIView* sub in view.subviews) {
        sub.layer.mask = nil;
    }
}

%hook T1AnimatedLaunchScreenView

- (void)layoutSubviews {
    %orig;
    // layoutSubviews re-installs the mask each pass, so re-strip after %orig.
    stripLaunchRevealMask((UIView*)self);
}

- (void)animateRevealWithCompletion:(id)completion {
    stripLaunchRevealMask((UIView*)self);

    [UIView animateWithDuration:0.5
                     animations:^{
                         for (UIView* sub in ((UIView*)self).subviews) {
                             sub.backgroundColor = [UIColor clearColor];
                         }
                     }];

    %orig;
}

%end
