//
//  Misc.x
//  NeoFreeBird
//

#import <CoreText/CoreText.h>
#import <CydiaSubstrate.h>
#import "HookHelpers.h"

%hook T1AccountAutoplayPolicy

- (id)initWithCurrentSettings:(id)settings
    currentNetworkReachabilityStatus:(id)status
    notificationCenter:(id)center
    ignoreCurrentSettingsWhenAutoplayingGif:(_Bool)ignore {
    return %orig(settings, status, center, NO);
}

- (id)initWithIgnoreCurrentSettingsWhenAutoplayingGif:(_Bool)ignore {
    return %orig(NO);
}

%end

// MARK: - Disable screenshot and screen recording detection

%hook NSNotificationCenter

- (id)addObserverForName:(NSNotificationName)name
                  object:(id)obj
                   queue:(NSOperationQueue*)queue
              usingBlock:(void (^)(NSNotification* note))block {
    if ([name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) {
        return %orig(name, obj, queue,
                         ^(NSNotification* note){});
    }
    if ([name isEqualToString:UIScreenCapturedDidChangeNotification]) {
        return %orig(name, obj, queue,
                         ^(NSNotification* note){});
    }

    return %orig;
}

- (void)addObserver:(id)observer
           selector:(SEL)aSelector
               name:(NSNotificationName)aName
             object:(id)anObject {
    if ([aName isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) {
        return;
    }
    if ([aName isEqualToString:UIScreenCapturedDidChangeNotification]) {
        return;
    }

    return %orig;
}

%end

%hook UIScreen
- (BOOL)isCaptured {
    return NO;
}
%end

%hook TUIFollowControlCustomScreenshot
- (void)didMoveToWindow {
    %orig;
    self.hidden = true;
    self.alpha = 0.0;
    self.userInteractionEnabled = false;
}
%end

// MARK: Hide the refresh pill at the top of the page that appears when new tweets are available
%hook TFNPillControl
- (void)didMoveToWindow {
    %orig;

    if ([BHTSettings boolForKey:@"hide_timeline_prompts"]) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

%end

%hook TFNFloatingActionButton
- (void)didMoveToWindow {
    %orig;

    if ([BHTSettings boolForKey:@"hide_tweet_button"]) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

%end