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
