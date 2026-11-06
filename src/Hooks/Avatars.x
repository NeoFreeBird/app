//
//  Avatars.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// Avatar style 2 is the circular default; style 3 is the rounded-square style
// the app itself uses for organization accounts (corner radius = width / 8).
// Coercing the style makes the views handle masking, corner radius, shadow
// layers and the image pipeline natively.

@interface TFNAvatarImageView : UIView
@property (nonatomic) NSInteger style;
@end

@interface TUIAvatarImageView : TFNAvatarImageView
@end

// Coerced views are marked so disabling the setting can restore just those,
// leaving avatars that are natively rounded squares alone.
static char kCoercedAvatarStyle;
static char kAvatarBarOriginalBackground;
static char kDashAvatarOriginalBorderWidth;

static void UpdateDashAvatarDecorations(UIView* avatar) {
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
            avatarClass, "_circularShadowLayer") : NULL;
        CALayer* shadow = shadowIvar ? object_getIvar(avatar, shadowIvar) : nil;
        if (shadow && !shadow.hidden) shadow.hidden = YES;
    } else if (borderWidth) {
        avatar.layer.borderWidth = borderWidth.doubleValue;
        objc_setAssociatedObject(avatar, &kDashAvatarOriginalBorderWidth, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static NSHashTable* AvatarBarItems(void) {
    static NSHashTable* items;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = [NSHashTable weakObjectsHashTable];
    });
    return items;
}

static void RefreshAvatarBarBackgrounds(void) {
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

static NSInteger CoercedStyle(UIView* view, NSInteger style) {
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

void applySquareAvatarsSetting(void) {
    BOOL enabled = [BHTSettings boolForKey:@"square_avatars"];
    Class avatarClass = objc_getClass("TFNAvatarImageView");

    RefreshAvatarBarBackgrounds();

    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        EnumerateSubviewsRecursively(window, ^(UIView* view) {
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

%hook TFNAvatarImageView

- (void)setStyle:(NSInteger)style {
    %orig(CoercedStyle(self, style));
}

%end

%hook _TtC11TwitterDash19DashAvatarImageView

- (void)layoutSubviews {
    %orig;
    UpdateDashAvatarDecorations((UIView*)self);
}

%end

// Force disable the Liquid Glass border
%group AvatarBarGlass
%hook _TtC11TwitterDash26TabRootAvatarBarButtonItem

- (void)setHidesSharedBackground:(BOOL)hidden {
    objc_setAssociatedObject(self, &kAvatarBarOriginalBackground, @(hidden),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [AvatarBarItems() addObject:self];
    %orig([BHTSettings boolForKey:@"square_avatars"] ? YES : hidden);
}

%end
%end

%ctor {
    %init(_ungrouped);
    if (class_getInstanceMethod([UIBarButtonItem class],
                                NSSelectorFromString(@"setHidesSharedBackground:"))) {
        %init(AvatarBarGlass);
    }
}

// TUIAvatarImageView picks its circular pre-clip image transformer from the
// incoming style, so coerce before its own logic runs. Its style mapping class
// method also feeds the Swift avatar views, whose setter is unreachable from
// ObjC.
%hook TUIAvatarImageView

- (void)setStyle:(NSInteger)style {
    %orig(CoercedStyle(self, style));
}

+ (NSInteger)avatarImageViewStyleWithProfileImageShape:(NSInteger)shape
                                          identityType:(NSInteger)identityType {
    return [BHTSettings boolForKey:@"square_avatars"] ? 3 : %orig;
}

%end

// Some fetch helpers install the circular transformer unconditionally, so
// images that get pre-clipped are rounded as squares instead of circles.
%hook UIImage

- (UIImage*)tfn_roundImageWithTargetDimensions:(CGSize)targetDimensions
                             targetContentMode:
                                 (UIViewContentMode)targetContentMode {
    if (![BHTSettings boolForKey:@"square_avatars"]) {
        return %orig;
    }

    if (targetDimensions.width <= 0 || targetDimensions.height <= 0) {
        return self;
    }

    CGRect imageRect =
        CGRectMake(0, 0, targetDimensions.width, targetDimensions.height);
    CGFloat cornerRadius =
        MIN(targetDimensions.width, targetDimensions.height) / 8.0;

    UIGraphicsBeginImageContextWithOptions(targetDimensions, NO, self.scale);
    if (!UIGraphicsGetCurrentContext()) {
        UIGraphicsEndImageContext();
        return self;
    }

    [[UIBezierPath bezierPathWithRoundedRect:imageRect
                                cornerRadius:cornerRadius] addClip];
    [self drawInRect:imageRect];

    UIImage* roundedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return roundedImage ?: self;
}

%end

%hook TFNCircularAvatarShadowLayer

- (void)setHidden:(BOOL)hidden {
    %orig([BHTSettings boolForKey:@"square_avatars"] ? YES : hidden);
}

%end
