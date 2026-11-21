#import "Chat.h"

void applyChatScreenTint(UIView* view) {
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        view.tintColor = CurrentAccentColor();
    }
}

BOOL shouldDropScreenshotProtection(UIView* protectionView) {
    if ([BHTSettings boolForKey:@"block_screenshot_detection"]) {
        return YES;
    }
    return !boolIvar(protectionView, "isProtectionEnabled", YES);
}

void disableSecureCanvas(UIView* protectionView) {
    UIView* canvas = objectIvar(protectionView, "secureCanvasView");
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
