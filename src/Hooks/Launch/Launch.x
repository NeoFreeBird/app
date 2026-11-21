#import "Launch.h"

%hook T1AnimatedLaunchScreenView
- (void)layoutSubviews {
    %orig;
    if (![BHTSettings boolForKey:@"blue_launch_screen"]) {
        return;
    }
    for (UIView* v in self.subviews) {
        v.backgroundColor = twitterColor();
    }
    self.layer.backgroundColor = twitterColor().CGColor;
    for (CALayer* layer in self.layer.sublayers) {
        layer.backgroundColor = twitterColor().CGColor;
    }
}

%end

// MARK: - LiveContainer startup hang (X 12.15+)
//
// X 12.15 gates boot on notification permission being *determined*:
// BootViewController asks for authorization and waits for the
// NotDetermined -> Denied/Authorized transition that normally arrives when the
// user answers the system prompt and the app becomes active again.
//
// A LiveContainer guest can never satisfy that. -requestAuthorizationWithOptions:
// fails instantly with granted=0 without ever presenting a prompt, and the status
// stays NotDetermined, so the gate re-asks forever, its signed-out completion is
// never invoked and the launch screen never clears -- a permanent hang on the
// logo for any fresh, signed-out install.
//
// Reporting the permission as denied (which is the truthful state: a guest cannot
// be granted it) lets boot proceed. Confirmed on X 12.15 / iOS 26.6: boot
// completes in ~0.6s instead of hanging indefinitely.
%hook UNNotificationSettings

- (NSInteger)authorizationStatus {
    NSInteger status = %orig;
    if (status == 0 /* UNAuthorizationStatusNotDetermined */ &&
        [BHTManager isLiveContainer]) {
        return 1; // UNAuthorizationStatusDenied
    }
    return status;
}

%end
