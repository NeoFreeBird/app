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
