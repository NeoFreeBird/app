#import "Chat.h"

// MARK: - Hide typing indicator

%hook Subsystem_ios_iosArm64_mainXChatConnectionManagerImpl
- (void)onMeTypingConversationId:(id)conversationID {
    if ([BHTSettings boolForKey:@"hide_typing_indicator"]) return;
    %orig(conversationID);
}
%end

// MARK: - Tint chat buttons

%hook TFNBarButtonItemButton
- (void)didMoveToWindow {
    %orig;
    applyChatScreenTint(self);
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

// MARK: - Chat screenshot protection

%hook UITextField
- (void)setSecureTextEntry:(BOOL)secure {
    if (secure && nfb_secureEntrySuppression > 0) {
        %orig(NO);
        return;
    }
    %orig;
}
%end

%hook _TtC16ChatConversation24ScreenshotProtectionView

- (void)didMoveToWindow {
    BOOL drop = shouldDropScreenshotProtection(self);
    if (drop) {
        if ([BHTSettings boolForKey:@"block_screenshot_detection"]) {
            setBoolIvar(self, "isProtectionEnabled", NO);
        }
        nfb_secureEntrySuppression++;
    }
    %orig;
    if (drop) {
        nfb_secureEntrySuppression--;
        disableSecureCanvas(self);
    }
}

- (void)layoutSubviews {
    BOOL drop = shouldDropScreenshotProtection(self);
    if (drop) {
        nfb_secureEntrySuppression++;
    }
    %orig;
    if (drop) {
        nfb_secureEntrySuppression--;
        disableSecureCanvas(self);
    }
}

%end
