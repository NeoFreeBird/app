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

// MARK: - Matching

static BOOL isChatWebSocketURL(NSURL* url) {
    if (!url) {
        return NO;
    }
    return [url.host isEqualToString:@"chat-ws.x.com"];
}

// The chat socket's typing heartbeat is a Thrift TBinaryProtocol struct whose
// second field -- the one that carries message text on a real send -- is an
// empty string. Frames captured while actually sending messages never hit
// -sendMessage: on this socket at all (message bodies go out over a separate
// HTTP/GraphQL write), so this shape reliably identifies the heartbeat:
//
//   0c 0001                  STRUCT, field 1 (envelope)
//     0b 0002 00000000        STRING, field 2, len=0   <- always empty on the ping
//     0b 0003 ...              STRING, field 3          -- sender user ID
//     ...
static const uint8_t TypingIndicatorFramePrefix[] = {0x0c, 0x00, 0x01, 0x0b, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00};

static BOOL isTypingIndicatorFrame(NSData* data) {
    if (data.length < sizeof(TypingIndicatorFramePrefix)) {
        return NO;
    }
    return memcmp(data.bytes, TypingIndicatorFramePrefix, sizeof(TypingIndicatorFramePrefix)) == 0;
}

// MARK: - Chat websocket tagging

static void* ChatSocketTagKey = &ChatSocketTagKey;

static void tagIfChatSocket(NSURLSessionWebSocketTask* task, NSURL* url) {
    if (task && isChatWebSocketURL(url)) {
        objc_setAssociatedObject(task, ChatSocketTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// MARK: - Dynamic swizzle for the real (private) websocket task class

typedef void (*SendMessageIMP)(id, SEL, NSURLSessionWebSocketMessage*, void (^)(NSError* _Nullable));
static SendMessageIMP OriginalSendMessageIMP;

static void nfb_sendMessageReplacement(id self, SEL _cmd, NSURLSessionWebSocketMessage* message,
                                       void (^completionHandler)(NSError* _Nullable)) {
    BOOL tagged = objc_getAssociatedObject(self, ChatSocketTagKey) != nil;
    if (tagged && message.data && isTypingIndicatorFrame(message.data) &&
        [BHTSettings boolForKey:@"hide_typing_indicator"]) {
        if (completionHandler) {
            completionHandler(nil);
        }
        return;
    }
    OriginalSendMessageIMP(self, _cmd, message, completionHandler);
}

static void nfb_swizzleSendMessageIfNeeded(NSURLSessionWebSocketTask* task) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class realClass = object_getClass(task);
        SEL selector = @selector(sendMessage:completionHandler:);
        Method method = class_getInstanceMethod(realClass, selector);
        if (!method) {
            return;
        }
        OriginalSendMessageIMP = (SendMessageIMP)method_getImplementation(method);
        method_setImplementation(method, (IMP)nfb_sendMessageReplacement);
    });
}

// MARK: - Hooks

%hook NSURLSession

- (NSURLSessionWebSocketTask*)webSocketTaskWithURL:(NSURL*)url {
    NSURLSessionWebSocketTask* task = %orig;
    nfb_swizzleSendMessageIfNeeded(task);
    tagIfChatSocket(task, url);
    return task;
}

- (NSURLSessionWebSocketTask*)webSocketTaskWithURL:(NSURL*)url protocols:(NSArray<NSString*>*)protocols {
    NSURLSessionWebSocketTask* task = %orig;
    nfb_swizzleSendMessageIfNeeded(task);
    tagIfChatSocket(task, url);
    return task;
}

- (NSURLSessionWebSocketTask*)webSocketTaskWithRequest:(NSURLRequest*)request {
    NSURLSessionWebSocketTask* task = %orig;
    nfb_swizzleSendMessageIfNeeded(task);
    tagIfChatSocket(task, request.URL);
    return task;
}

%end

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
