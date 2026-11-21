#import "InterfaceDirection.h"

// MARK: - Disable RTL

%hook TFNAttributedTextModel

- (void)setAttributedString:(NSAttributedString*)attributedString {
    if (![BHTSettings boolForKey:@"disable_rtl"] || attributedString.length == 0) {
        return %orig;
    }

    NSMutableAttributedString* text = [attributedString mutableCopy];
    [attributedString
        enumerateAttribute:NSParagraphStyleAttributeName
                   inRange:NSMakeRange(0, attributedString.length)
                   options:0
                usingBlock:^(id value, NSRange range, BOOL* stop) {
                    // Some models carry a raw CTParagraphStyleRef under the same key.
                    if (value != nil && ![value isKindOfClass:[NSParagraphStyle class]]) {
                        if (CFGetTypeID((__bridge CFTypeRef)value) == CTParagraphStyleGetTypeID()) {
                            CTParagraphStyleRef ltrStyle =
                                CreateLTRParagraphStyle((__bridge CTParagraphStyleRef)value);
                            [text addAttribute:NSParagraphStyleAttributeName
                                         value:(__bridge_transfer id)ltrStyle
                                         range:range];
                        }
                        return;
                    }

                    NSMutableParagraphStyle* style =
                        value ? [value mutableCopy] : [NSMutableParagraphStyle new];
                    style.baseWritingDirection = NSWritingDirectionLeftToRight;
                    [text addAttribute:NSParagraphStyleAttributeName value:style range:range];
                }];

    %orig(text);
}

%end

%hook NSString

- (BOOL)tfs_plainTextShouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

- (BOOL)tfs_statusTextShouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

- (BOOL)tfs_labelTextShouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

%end

%hook TFNTwitterStatus

- (BOOL)shouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

%end

%hook TFNTwitterDisplayTextModel

- (BOOL)_tfn_shouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

%end

%hook UIView
+ (UIUserInterfaceLayoutDirection)userInterfaceLayoutDirectionForSemanticContentAttribute:(UISemanticContentAttribute)attribute {
    return [BHTSettings boolForKey:@"disable_rtl"] ? UIUserInterfaceLayoutDirectionLeftToRight : %orig;
}
+ (UIUserInterfaceLayoutDirection)userInterfaceLayoutDirectionForSemanticContentAttribute:(UISemanticContentAttribute)attribute relativeToLayoutDirection:(UIUserInterfaceLayoutDirection)direction {
    return [BHTSettings boolForKey:@"disable_rtl"] ? UIUserInterfaceLayoutDirectionLeftToRight : %orig;
}
- (UIUserInterfaceLayoutDirection)effectiveUserInterfaceLayoutDirection {
    return [BHTSettings boolForKey:@"disable_rtl"] ? UIUserInterfaceLayoutDirectionLeftToRight : %orig;
}
- (UISemanticContentAttribute)semanticContentAttribute {
    UISemanticContentAttribute attribute = %orig;
    if ([BHTSettings boolForKey:@"disable_rtl"] && attribute != UISemanticContentAttributePlayback && attribute != UISemanticContentAttributeSpatial) {
        return UISemanticContentAttributeForceLeftToRight;
    }
    return attribute;
}
%end

%hook UIApplication
- (UIUserInterfaceLayoutDirection)userInterfaceLayoutDirection {
    return [BHTSettings boolForKey:@"disable_rtl"] ? UIUserInterfaceLayoutDirectionLeftToRight : %orig;
}
%end

%hook UITraitCollection
- (UITraitEnvironmentLayoutDirection)layoutDirection {
    return [BHTSettings boolForKey:@"disable_rtl"] ? UITraitEnvironmentLayoutDirectionLeftToRight : %orig;
}
%end

%group TwitterMirroring
%hook UIView
+ (BOOL)tfn_isRightToLeftTransformSystemActive {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}
%end
%end

    %ctor {
    %init;
    if (class_getClassMethod(UIView.class, @selector(tfn_isRightToLeftTransformSystemActive))) {
        %init(TwitterMirroring);
    }
}
