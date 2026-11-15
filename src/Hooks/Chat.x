//
//  Chat.x
//  NeoFreeBird
//
//  XChat's typing indicator has two carriers: a one-off POST to the
//  jot/client_event analytics endpoint, and a periodic push over the
//  persistent chat-ws.x.com websocket. The jot POST is blocked outright
//  below (a normal NSURLSession data task). The websocket also carries
//  message delivery/read-receipts/presence, so it can't be blocked outright
//  -- instead, only the specific outgoing frame shape used for the typing
//  heartbeat is dropped; everything else on the socket passes through
//  untouched. See the field-shape comment on isTypingIndicatorFrame for how
//  that shape was identified.
//

#import <string.h>
#import "HookHelpers.h"

// MARK: - Hide typing indicator

%hook Subsystem_ios_iosArm64_mainXChatConnectionManagerImpl
- (void)onMeTypingConversationId:(id)conversationID {
    if ([BHTSettings boolForKey:@"hide_typing_indicator"]) return;
    %orig(conversationID);
}
%end

// MARK: - Tint chat buttons

static void nfb_applyChatScreenTint(UIView* view) {
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        view.tintColor = CurrentAccentColor();
    }
}

%hook TFNBarButtonItemButton
- (void)didMoveToWindow {
    %orig;
    nfb_applyChatScreenTint(self);
}
%end

// MARK: - Chat screenshot protection

static NSInteger nfb_secureEntrySuppression = 0;

static void* NFBNeutralizedCanvasKey = &NFBNeutralizedCanvasKey;

static void nfb_disableSecureCanvas(UIView* protectionView) {
    UIView* canvas = nfb_objectIvar(protectionView, "secureCanvasView");
    if (!canvas ||
        objc_getAssociatedObject(protectionView, NFBNeutralizedCanvasKey) == canvas) {
        return;
    }

    // The field is kept in a separate ivar (it has to be retained somewhere for
    // the canvas to keep working)
    UITextField* owner = nil;
    unsigned int count = 0;
    Ivar* ivars = class_copyIvarList(object_getClass(protectionView), &count);
    for (unsigned int i = 0; i < count && !owner; i++) {
        const char* type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') {
            continue;
        }
        id value = object_getIvar(protectionView, ivars[i]);
        if ([value isKindOfClass:[UITextField class]]) {
            owner = value;
        }
    }
    free(ivars);

    if (!owner && [canvas.superview isKindOfClass:[UITextField class]]) {
        owner = (UITextField*)canvas.superview;
    }

    if (owner) {
        owner.secureTextEntry = NO;
    } else {
        for (UIView* content in [canvas.subviews copy]) {
            BOOL usesAutoLayout = !content.translatesAutoresizingMaskIntoConstraints;
            CGRect frame = [canvas convertRect:content.frame toView:protectionView];
            [protectionView addSubview:content];
            if (usesAutoLayout) {
                [NSLayoutConstraint activateConstraints:@[
                    [content.leadingAnchor constraintEqualToAnchor:protectionView.leadingAnchor],
                    [content.trailingAnchor constraintEqualToAnchor:protectionView.trailingAnchor],
                    [content.topAnchor constraintEqualToAnchor:protectionView.topAnchor],
                    [content.bottomAnchor constraintEqualToAnchor:protectionView.bottomAnchor],
                ]];
            } else {
                content.frame = frame;
                content.autoresizingMask =
                    UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            }
        }
        [canvas removeFromSuperview];
    }

    objc_setAssociatedObject(protectionView, NFBNeutralizedCanvasKey, canvas,
                             OBJC_ASSOCIATION_ASSIGN);
}

static BOOL nfb_shouldDropScreenshotProtection(UIView* protectionView) {
    if ([BHTSettings boolForKey:@"block_screenshot_detection"]) {
        return YES;
    }
    return !nfb_boolIvar(protectionView, "isProtectionEnabled", YES);
}

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
    BOOL drop = nfb_shouldDropScreenshotProtection(self);
    if (drop) {
        if ([BHTSettings boolForKey:@"block_screenshot_detection"]) {
            nfb_setBoolIvar(self, "isProtectionEnabled", NO);
        }
        nfb_secureEntrySuppression++;
    }
    %orig;
    if (drop) {
        nfb_secureEntrySuppression--;
        nfb_disableSecureCanvas(self);
    }
}

- (void)layoutSubviews {
    BOOL drop = nfb_shouldDropScreenshotProtection(self);
    if (drop) {
        nfb_secureEntrySuppression++;
    }
    %orig;
    if (drop) {
        nfb_secureEntrySuppression--;
        nfb_disableSecureCanvas(self);
    }
}

%end
