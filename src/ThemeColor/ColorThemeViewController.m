//
//  ColorThemeViewController.m
//  NeoFreeBird
//
//  Created by Bandar Alruwaili on 10/12/2023.
//  Modified by actuallyaridan on 25/05/2025.
//
//  Clones the native accent picker (ColorThemePickerItem).
//

#import "ColorThemeViewController.h"
#import <UIKit/UIKit.h>
#import "ColorSwatchControl.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Core/TwitterChirpFont.h"
#import "Headers/TFNHeaders.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/Palette.h"

// Mirrors CurrentAccentColor's precedence (our override, then Twitter's own
// option) so the default swatch shows selected before any change.
static NSInteger CurrentSelectedColorOption(void) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"bh_color_theme_selectedColor"]) {
        return [defaults integerForKey:@"bh_color_theme_selectedColor"];
    }
    // Twitter stores its default accent (blue) as option 0, and resets to 0 on
    // launch; our swatches are options 1-6, so map 0 (or unset) to blue.
    NSInteger option = [defaults integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    return option >= 1 ? option : 1;
}

// The accent picker ships no localized colour names, so the swatches borrow the
// Fleets accessibility labels for the same six colours.
static const NSUInteger kAccentOptionCount = 6;
static NSInteger const kCustomAccentOption = -1;
static NSString* const kCustomAccentColorKey = @"bh_color_theme_customColor";
static NSString* const kAccentColorNames[kAccentOptionCount] = {@"BLUE", @"YELLOW", @"RED",
                                                                @"PURPLE", @"ORANGE", @"GREEN"};

static UIColor* NativeAccentColor(NSUInteger option) {
    id palette =
        [[[objc_getClass("TAEColorSettings") sharedSettings] currentColorPalette] colorPalette];
    UIColor* color = [palette primaryColorForOption:option];
    return [color isKindOfClass:[UIColor class]] ? color : nil;
}

@interface ColorThemeViewController () <UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) NSMutableArray<ColorSwatchControl*>* swatches;
@property (nonatomic, strong) ColorSwatchControl* customSwatch;
@end

@implementation ColorThemeViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [Palette currentBackgroundColor];

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_DETAIL"];
    detail.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    detail.textColor = [UIColor secondaryLabelColor];
    detail.numberOfLines = 0;
    [self.view addSubview:detail];

    // Evenly-spread row of swatches, matching the native picker's flex layout.
    UIStackView* row = [[UIStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    // Fill so each swatch spans the row height as a real tap target.
    row.alignment = UIStackViewAlignmentFill;
    [self.view addSubview:row];

    self.swatches = [NSMutableArray new];
    for (NSUInteger option = 1; option <= kAccentOptionCount; option++) {
        ColorSwatchControl* swatch = [[ColorSwatchControl alloc] init];
        swatch.translatesAutoresizingMaskIntoConstraints = NO;
        swatch.colorID = option;
        swatch.isAccessibilityElement = YES;
        swatch.accessibilityLabel = [[BHTBundle sharedBundle]
            localizedTwitterStringForKey:[NSString
                                             stringWithFormat:@"FLEETS_COLOR_%@_ACCESSIBILITY_LABEL",
                                                              kAccentColorNames[option - 1]]];
        [swatch setSwatchColor:NativeAccentColor(option)];
        [swatch addTarget:self
                      action:@selector(swatchTapped:)
            forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:swatch];
        [self.swatches addObject:swatch];
    }

    self.customSwatch = [[ColorSwatchControl alloc] init];
    self.customSwatch.translatesAutoresizingMaskIntoConstraints = NO;
    self.customSwatch.colorID = kCustomAccentOption;
    self.customSwatch.isAccessibilityElement = YES;
    self.customSwatch.accessibilityLabel = @"Custom color";
    UIColor* customColor = [self storedCustomAccentColor] ?: [UIColor systemBlueColor];
    [self.customSwatch setSwatchColor:customColor];
    [self.customSwatch addTarget:self
                          action:@selector(customSwatchTapped:)
                forControlEvents:UIControlEventTouchUpInside];
    [row addArrangedSubview:self.customSwatch];

    [NSLayoutConstraint activateConstraints:@[
        [detail.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                         constant:16],
        [detail.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                             constant:16],
        [detail.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                              constant:-16],

        [row.topAnchor constraintEqualToAnchor:detail.bottomAnchor
                                      constant:16],
        [row.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                          constant:16],
        [row.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                           constant:-16],
        [row.heightAnchor constraintEqualToConstant:52]
    ]];

    [self refreshSelection];
}

#pragma mark - Selection

- (void)refreshSelection {
    NSInteger selected = CurrentSelectedColorOption();
    for (ColorSwatchControl* swatch in self.swatches) {
        [swatch setSwatchSelected:(swatch.colorID == selected)];
    }
    [self.customSwatch setSwatchSelected:(selected == kCustomAccentOption)];
}

- (UIColor*)storedCustomAccentColor {
    NSArray<NSNumber*>* components = [[NSUserDefaults standardUserDefaults]
        arrayForKey:kCustomAccentColorKey];
    if (components.count != 4) return nil;
    return [UIColor colorWithRed:components[0].doubleValue
                           green:components[1].doubleValue
                            blue:components[2].doubleValue
                           alpha:components[3].doubleValue];
}

- (void)customSwatchTapped:(id)sender {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController* picker = [UIColorPickerViewController new];
        picker.delegate = self;
        picker.selectedColor = [self storedCustomAccentColor] ?: [UIColor systemBlueColor];
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController*)viewController API_AVAILABLE(ios(14.0)) {
    UIColor* color = viewController.selectedColor;
    CGFloat red = 0, green = 0, blue = 0, alpha = 1;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) return;
    [[NSUserDefaults standardUserDefaults] setObject:@[@(red), @(green), @(blue), @(alpha)]
                                              forKey:kCustomAccentColorKey];
    [[NSUserDefaults standardUserDefaults] setInteger:kCustomAccentOption
                                               forKey:@"bh_color_theme_selectedColor"];
    [self.customSwatch setSwatchColor:color];
    [self refreshSelection];
    [self reapplyAccentToLiveViews];
}

- (void)swatchTapped:(ColorSwatchControl*)swatch {
    [[NSUserDefaults standardUserDefaults] setInteger:swatch.colorID
                                               forKey:@"bh_color_theme_selectedColor"];
    changeTwitterColor(swatch.colorID);

    [self refreshSelection];
    [self reapplyAccentToLiveViews];
}

static void reapplySegmentedCaretAccent(UIView* view) {
    if ([view respondsToSelector:@selector(nfb_applyGlassTabAccent)]) {
        [view performSelector:@selector(nfb_applyGlassTabAccent)];
    }
    static Class caretClass;
    static Class tabBarClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        caretClass = NSClassFromString(@"_TtC10TFNUISwift31LegacySegmentedHighlightBarView");
        tabBarClass = NSClassFromString(@"_TtC10TFNUISwift25LegacySegmentedTabBarView");
    });

    if (caretClass && [view isKindOfClass:caretClass]) {
        view.backgroundColor = CurrentAccentColor();
    }

    if (tabBarClass && [view isKindOfClass:tabBarClass]) {
        _TtC10TFNUISwift25LegacySegmentedTabBarView* tabBar =
            (_TtC10TFNUISwift25LegacySegmentedTabBarView*)view;
        _TtC10TFNUISwift26LegacySegmentedTabBarStyle* style = tabBar.style;
        if (style) {
            style.highlightBarColor = CurrentAccentColor();
            tabBar.style = style;
        }
    }
    for (UIView* subview in view.subviews) {
        reapplySegmentedCaretAccent(subview);
    }
}

- (void)reapplyAccentToLiveViews {
    BHTReapplyAccentTintedIcons();

    Class t1TabBarVCClass = NSClassFromString(@"T1TabBarViewController");
    if (!t1TabBarVCClass) return;

    UIWindow* window = nil;
    for (UIWindowScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
            if ([scene.delegate respondsToSelector:@selector(window)]) {
                window = [(id)scene.delegate window];
            } else {
                for (UIWindow* w in [(id)scene windows]) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
            }
            if (window) break;
        }
    }
    if (!window) return;

    NSMutableArray* stack = [NSMutableArray arrayWithObject:window.rootViewController];
    while (stack.count) {
        UIViewController* vc = stack.firstObject;
        [stack removeObjectAtIndex:0];
        if ([vc isKindOfClass:t1TabBarVCClass] && [vc respondsToSelector:@selector(tabViews)]) {
            for (id tab in [vc valueForKey:@"tabViews"]) {
                if ([tab respondsToSelector:@selector(applyCurrentThemeToIcon)]) {
                    [tab performSelector:@selector(applyCurrentThemeToIcon)];
                }
            }
        }
        if (vc.presentedViewController) [stack addObject:vc.presentedViewController];
        if ([vc isKindOfClass:[UINavigationController class]])
            [stack addObjectsFromArray:((UINavigationController*)vc).viewControllers];
        if ([vc isKindOfClass:[UITabBarController class]])
            [stack addObjectsFromArray:((UITabBarController*)vc).viewControllers];
        [stack addObjectsFromArray:vc.childViewControllers];
    }

    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        reapplySegmentedCaretAccent(window);
    }
}

@end
