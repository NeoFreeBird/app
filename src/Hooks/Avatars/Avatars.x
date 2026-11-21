#import "Avatars.h"

// Avatar style 2 is the circular default; style 3 is the rounded-square style
// the app itself uses for organization accounts (corner radius = width / 8).
// Coercing the style makes the views handle masking, corner radius, shadow
// layers and the image pipeline natively.

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
