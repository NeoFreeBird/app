#import "AppLifecycle.h"

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

%hook T1AnimatedLaunchScreenView

- (void)layoutSubviews {
    %orig;
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

%hook T1ViewControllerScribeEventObserver
- (void)viewControllerApplicationDidBecomeActive:(id)active {
    if ([BHTSettings boolForKey:@"no_focus_lost"]) {
        return;
    }
    %orig(active);
}
%end
