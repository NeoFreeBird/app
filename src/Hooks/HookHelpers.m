//
//  BHTHookHelpers.m
//  NeoFreeBird
//

#import "HookHelpers.h"

void EnumerateSubviewsRecursively(UIView* view,
                                  void (^block)(UIView* currentView)) {
    if (!view || !block)
        return;

    // Hidden branches never need live restyling, so skip them entirely.
    if (view.hidden || view.alpha <= 0.01)
        return;

    block(view);

    // Depth cap; a static counter is fine since traversal only runs on the main
    // thread.
    static NSInteger recursionDepth = 0;
    if (recursionDepth > 15)
        return;

    recursionDepth++;
    for (UIView* subview in view.subviews) {
        EnumerateSubviewsRecursively(subview, block);
    }
    recursionDepth--;
}

// MARK: - Accent-tinted icon tracking

static NSHashTable<UIView*>* AccentTintedIcons(void) {
    static NSHashTable* icons;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        icons = [NSHashTable weakObjectsHashTable];
    });
    return icons;
}

void BHTMarkAccentTintedIcon(UIView* view, BOOL tinted) {
    if (!view)
        return;

    if (tinted) {
        [AccentTintedIcons() addObject:view];
    } else {
        [AccentTintedIcons() removeObject:view];
    }
}

void BHTReapplyAccentTintedIcons(void) {
    UIColor* accent = CurrentAccentColor();
    for (UIView* icon in AccentTintedIcons().allObjects) {
        icon.tintColor = accent;
    }
}

// Module content reaches the section arrays wrapped in TFNDataViewItem (the
// real view model is its -item); standalone timeline items are the view model
// directly.
id unwrapDataViewItem(id item) {
    if ([item isKindOfClass:objc_getClass("TFNDataViewItem")] &&
        [item respondsToSelector:@selector(item)]) {
        return [item performSelector:@selector(item)];
    }

    return item;
}

BOOL IsModuleHeaderItem(id item) {
    return [NSStringFromClass([unwrapDataViewItem(item) classForCoder])
        isEqualToString:@"TwitterURT.URTModuleHeaderViewModel"];
}

BOOL IsModuleFooterItem(id item) {
    return [NSStringFromClass([unwrapDataViewItem(item) classForCoder])
        isEqualToString:@"TwitterURT.URTModuleFooterViewModel"];
}

// A module renders as a consecutive run of header, content, footer. When a
// module's content is removed entirely, mark its header and footer too.
void MarkEmptiedModuleChrome(NSArray* items, NSMutableIndexSet* removed) {
    NSUInteger count = items.count;

    for (NSUInteger i = 0; i < count; i++) {
        if ([removed containsIndex:i] || !IsModuleHeaderItem(items[i])) {
            continue;
        }

        NSUInteger contentCount = 0;
        BOOL contentRemoved = YES;
        NSUInteger j = i + 1;
        while (j < count && !IsModuleHeaderItem(items[j]) &&
               !IsModuleFooterItem(items[j])) {
            contentCount++;
            if (![removed containsIndex:j]) {
                contentRemoved = NO;
            }
            j++;
        }

        if (contentCount > 0 && contentRemoved) {
            [removed addIndex:i];
            if (j < count && IsModuleFooterItem(items[j])) {
                [removed addIndex:j];
            }
        }
    }
}

UIColor* CurrentAccentColor(void) {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    if (!TAEColorSettingsCls) {
        return [UIColor systemBlueColor];
    }

    id settings = [TAEColorSettingsCls sharedSettings];
    id current = [settings currentColorPalette];
    id palette = [current colorPalette];
    NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];

    NSArray<NSNumber*>* custom = [defs arrayForKey:@"bh_color_theme_customColor"];
    if ([defs integerForKey:@"bh_color_theme_selectedColor"] == -1 && custom.count == 4) {
        return [UIColor colorWithRed:custom[0].doubleValue
                               green:custom[1].doubleValue
                                blue:custom[2].doubleValue
                               alpha:custom[3].doubleValue];
    }

    // The tweak's stored pick wins over Twitter's own colour option.
    if ([defs objectForKey:@"bh_color_theme_selectedColor"]) {
        NSInteger opt = [defs integerForKey:@"bh_color_theme_selectedColor"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    if ([defs objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"]) {
        NSInteger opt =
            [defs integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
        return [palette primaryColorForOption:opt] ?: [UIColor systemBlueColor];
    }

    return [UIColor systemBlueColor];
}

NSString* formatNumberWithSuffix(long long number) {
    if (number < 1000) {
        return [NSString stringWithFormat:@"%lld", number];
    } else if (number < 1000000) {
        return [NSString stringWithFormat:@"%.1fK", number / 1000.0];
    } else if (number < 1000000000) {
        return [NSString stringWithFormat:@"%.1fM", number / 1000000.0];
    } else {
        return [NSString stringWithFormat:@"%.1fB", number / 1000000000.0];
    }
}
