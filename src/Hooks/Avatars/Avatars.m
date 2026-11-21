#import "Avatars.h"

void UpdateDashAvatarDecorations(UIView* avatar) {
    Class dashAvatarClass = objc_getClass("_TtC11TwitterDash19DashAvatarImageView");
    if (!dashAvatarClass || ![avatar isKindOfClass:dashAvatarClass]) return;

    BOOL square = [BHTSettings boolForKey:@"square_avatars"];
    NSNumber* borderWidth = objc_getAssociatedObject(avatar,
                                                     &kDashAvatarOriginalBorderWidth);
    if (square) {
        if (!borderWidth) {
            objc_setAssociatedObject(avatar, &kDashAvatarOriginalBorderWidth,
                                     @(avatar.layer.borderWidth),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (avatar.layer.borderWidth != 0) avatar.layer.borderWidth = 0;
        Class avatarClass = objc_getClass("TFNAvatarImageView");
        Ivar shadowIvar = avatarClass ? class_getInstanceVariable(
                                            avatarClass, "_circularShadowLayer")
                                      : NULL;
        CALayer* shadow = shadowIvar ? object_getIvar(avatar, shadowIvar) : nil;
        if (shadow && !shadow.hidden) shadow.hidden = YES;
    } else if (borderWidth) {
        avatar.layer.borderWidth = borderWidth.doubleValue;
        objc_setAssociatedObject(avatar, &kDashAvatarOriginalBorderWidth, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

NSHashTable* AvatarBarItems(void) {
    static NSHashTable* items;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = [NSHashTable weakObjectsHashTable];
    });
    return items;
}

void RefreshAvatarBarBackgrounds(void) {
    SEL setter = NSSelectorFromString(@"setHidesSharedBackground:");
    for (UIBarButtonItem* item in AvatarBarItems().allObjects) {
        NSNumber* original = objc_getAssociatedObject(item,
                                                      &kAvatarBarOriginalBackground);
        if (original && [item respondsToSelector:setter]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(item, setter,
                                                    original.boolValue);
        }
    }
}

NSInteger CoercedStyle(UIView* view, NSInteger style) {
    if (style == 2) {
        if ([BHTSettings boolForKey:@"square_avatars"]) {
            objc_setAssociatedObject(view, &kCoercedAvatarStyle, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return 3;
        }
        objc_setAssociatedObject(view, &kCoercedAvatarStyle, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return style;
}

BOOL UpdateFleetBorderStyle(UIView* view) {
    Class borderClass = objc_getClass("_TtC14T1TwitterSwift25FleetLineNestedBorderView");
    if (!borderClass || ![view isKindOfClass:borderClass]) return NO;

    Ivar styleIvar = class_getInstanceVariable(borderClass, "style");
    Ivar nextIvar = class_getInstanceVariable(borderClass, "pillCornerRadius");
    if (!styleIvar || !nextIvar) return NO;
    ptrdiff_t offset = ivar_getOffset(styleIvar);
    size_t size = class_getInstanceSize(object_getClass(view));
    if (offset < (ptrdiff_t)sizeof(void*) ||
        (size_t)offset + sizeof(NSInteger) > size ||
        ivar_getOffset(nextIvar) - offset != sizeof(NSInteger)) {
        return NO;
    }

    unsigned char* storage = (unsigned char*)(__bridge void*)view + offset;
    NSInteger style;
    memcpy(&style, storage, sizeof(style));
    NSInteger updatedStyle = style;
    NSNumber* original = objc_getAssociatedObject(view, &kFleetBorderOriginalStyle);
    if ([BHTSettings boolForKey:@"square_avatars"]) {
        if (style == 2) {
            objc_setAssociatedObject(view, &kFleetBorderOriginalStyle, @2,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            updatedStyle = 3;
        }
    } else if (original) {
        if (style == 3) updatedStyle = original.integerValue;
        objc_setAssociatedObject(view, &kFleetBorderOriginalStyle, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (updatedStyle == style) return NO;
    memcpy(storage, &updatedStyle, sizeof(updatedStyle));
    return YES;
}

void applySquareAvatarsSetting(void) {
    BOOL enabled = [BHTSettings boolForKey:@"square_avatars"];
    Class avatarClass = objc_getClass("TFNAvatarImageView");

    RefreshAvatarBarBackgrounds();

    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        EnumerateSubviewsRecursively(window, ^(UIView* view) {
            if (UpdateFleetBorderStyle(view)) {
                [view setNeedsLayout];
            }
            if (![view isKindOfClass:avatarClass]) {
                return;
            }

            TFNAvatarImageView* avatar = (TFNAvatarImageView*)view;
            if (enabled
                    ? avatar.style == 2
                    : objc_getAssociatedObject(avatar, &kCoercedAvatarStyle) != nil) {
                // Re-sent as circular; the hook coerces it when the setting is on.
                [avatar setStyle:2];
            }
            UpdateDashAvatarDecorations(avatar);
        });
    }
}
