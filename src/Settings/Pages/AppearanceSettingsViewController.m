//
//  AppearanceSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/AppearanceSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/Helpers.h"
#import "Headers/TWHeaders.h"
#import "Settings/ModernSettingsCells.h"

@interface AppearanceSettingsViewController () <UIFontPickerViewControllerDelegate>
@end

@implementation AppearanceSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.estimatedRowHeight = 60;
    [self.tableView registerClass:[ModernSettingsSimpleButtonCell class]
           forCellReuseIdentifier:@"SimpleButtonCell"];
}

- (NSString*)pageKey {
    return @"appearance";
}

- (void)updateVisibleToggles {
    [super updateVisibleToggles];
    // macOS doesn't support alternate app icons, so hide the row entirely.
    if (is_Mac()) {
        NSPredicate* notAppIcon = [NSPredicate predicateWithBlock:^BOOL(NSDictionary* toggle, NSDictionary* bindings) {
            return ![toggle[@"action"] isEqualToString:@"showAppIconViewController:"];
        }];
        self.visibleToggles = [self.visibleToggles filteredArrayUsingPredicate:notAppIcon];
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* settingData = self.visibleToggles[indexPath.row];
    if ([settingData[@"type"] isEqualToString:@"button"]) {
        ModernSettingsSimpleButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"SimpleButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
        [cell configureWithTitle:title];
        return cell;
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

#pragma mark - Sub-page Navigation

- (void)showThemeViewController:(NSDictionary*)sender {
    Class ColorThemeViewControllerClass = objc_getClass("ColorThemeViewController");
    if (ColorThemeViewControllerClass) {
        UIViewController* themeVC = [[ColorThemeViewControllerClass alloc] init];
        if (self.account) {
            [themeVC.navigationItem
                setTitleView:
                    [objc_getClass("TFNTitleView")
                        titleViewWithTitle:[[BHTBundle sharedBundle]
                                               localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_TITLE"]
                                  subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:themeVC animated:YES];
    }
}

- (void)showAppIconViewController:(NSDictionary*)sender {
    Class AppIconViewControllerClass = objc_getClass("AppIconViewController");
    if (AppIconViewControllerClass) {
        UIViewController* appIconVC = [[AppIconViewControllerClass alloc] init];
        if (self.account) {
            [appIconVC.navigationItem
                setTitleView:[objc_getClass("TFNTitleView")
                                 titleViewWithTitle:[[BHTBundle sharedBundle]
                                                        localizedStringForKey:
                                                            @"SUBSCRIPTION_APP_ICON_SETTINGS_TITLE"]
                                           subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:appIconVC animated:YES];
    }
}

- (void)showCustomTabBarVC:(NSDictionary*)sender {
    UIViewController* customTabBarVC = [CustomTabBarUtility editorForAccount:self.account];
    if (customTabBarVC) {
        // X supplies the native editor's own title and account subtitle.
        if (self.account && ![CustomTabBarUtility usesNativeEditor]) {
            [customTabBarVC.navigationItem
                setTitleView:[objc_getClass("TFNTitleView")
                                 titleViewWithTitle:[[BHTBundle sharedBundle]
                                                        localizedStringForKey:
                                                            @"CUSTOM_TAB_BAR_SETTINGS_NAVIGATION_TITLE"]
                                           subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:customTabBarVC animated:YES];
    } else {
        BHTBundle* bundle = [BHTBundle sharedBundle];
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:[bundle localizedStringForKey:@"CUSTOM_TAB_BAR_SETTINGS_NAVIGATION_TITLE"]
                             message:[bundle localizedStringForKey:@"UNKNOWN_ERROR"]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"OK_ACTION_LABEL"]
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - Tab Bar Refresh

- (void)refreshAllTabViewsWithTheming {
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [self refreshTabViewsWithThemingInView:window.rootViewController.view];
        }
    }
}

- (void)refreshTabViewsWithThemingInView:(UIView*)view {
    if ([view respondsToSelector:@selector(nfb_refreshGlassTabLabels)]) {
        [view performSelector:@selector(nfb_refreshGlassTabLabels)];
    }
    if ([view respondsToSelector:@selector(nfb_applyGlassTabAccent)]) {
        [view performSelector:@selector(nfb_applyGlassTabAccent)];
    }
    if ([view isKindOfClass:NSClassFromString(@"T1TabView")]) {
        T1TabView* tabView = (T1TabView*)view;
        [tabView _t1_updateImageViewAnimated:NO];
        if ([view respondsToSelector:@selector(_t1_layoutForTabBar)]) {
            [view performSelector:@selector(_t1_layoutForTabBar)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMaximized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMaximized)];
        }
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMinimized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMinimized)];
        }
    }

    for (UIView* subview in view.subviews) {
        [self refreshTabViewsWithThemingInView:subview];
    }
}

- (void)refreshAllTabViews {
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [self refreshTabViewsInView:window.rootViewController.view];
        }
    }
}

- (void)refreshTabViewsInView:(UIView*)view {
    if ([view respondsToSelector:@selector(nfb_refreshGlassTabLabels)]) {
        [view performSelector:@selector(nfb_refreshGlassTabLabels)];
    }
    if ([view isKindOfClass:NSClassFromString(@"T1TabView")]) {
        [view setNeedsLayout];
        [view layoutIfNeeded];
        if ([view respondsToSelector:@selector(_t1_layoutBadgeViewMaximized)]) {
            [view performSelector:@selector(_t1_layoutBadgeViewMaximized)];
        }
    }

    for (UIView* subview in view.subviews) {
        [self refreshTabViewsInView:subview];
    }
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"tab_bar_theming"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshAllTabViewsWithTheming];
        });
    } else if ([key isEqualToString:@"restore_tab_labels"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshAllTabViews];
        });
    } else if ([key isEqualToString:@"enable_dim_theme"]) {
        UIAlertController* alertController =
            [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle]
                                                            localizedStringForKey:@"DIM_THEME_RESTART_ALERT_TITLE"]
                                                message:[[BHTBundle sharedBundle]
                                                            localizedStringForKey:@"DIM_THEME_RESTART_ALERT_MESSAGE"]
                                         preferredStyle:UIAlertControllerStyleAlert];

        alertController.modalPresentationStyle = UIModalPresentationFullScreen;
        UIAlertAction* restartAction = [UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                                          localizedStringForKey:@"DIM_THEME_RESTART_ALERT_RESTART_BUTTON"]
                                                                style:UIAlertActionStyleDestructive
                                                              handler:^(UIAlertAction* action) {
                                                                  exit(0);
                                                              }];
        [alertController addAction:restartAction];
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

#pragma mark - Font Pickers

- (void)showRegularFontPicker:(NSDictionary*)sender {
    UIFontPickerViewControllerConfiguration* configuration =
        [[UIFontPickerViewControllerConfiguration alloc] init];
    [configuration setFilteredTraits:UIFontDescriptorClassMask];
    [configuration setIncludeFaces:NO];
    UIFontPickerViewController* fontPicker =
        [[UIFontPickerViewController alloc] initWithConfiguration:configuration];
    fontPicker.delegate = (id<UIFontPickerViewControllerDelegate>)self;
    objc_setAssociatedObject(fontPicker, @"fontType", @"regular", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.account) {
        [fontPicker.navigationItem
            setTitleView:
                [objc_getClass("TFNTitleView")
                    titleViewWithTitle:[[BHTBundle sharedBundle]
                                           localizedStringForKey:@"REGULAR_FONTS_PICKER_OPTION_TITLE"]
                              subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title =
            [[BHTBundle sharedBundle] localizedStringForKey:@"REGULAR_FONTS_PICKER_OPTION_TITLE"];
    }
    [self.navigationController pushViewController:fontPicker animated:YES];
}

- (void)showBoldFontPicker:(NSDictionary*)sender {
    UIFontPickerViewControllerConfiguration* configuration =
        [[UIFontPickerViewControllerConfiguration alloc] init];
    [configuration setIncludeFaces:YES];
    [configuration setFilteredTraits:UIFontDescriptorClassMask];
    UIFontPickerViewController* fontPicker =
        [[UIFontPickerViewController alloc] initWithConfiguration:configuration];
    fontPicker.delegate = (id<UIFontPickerViewControllerDelegate>)self;
    objc_setAssociatedObject(fontPicker, @"fontType", @"bold", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.account) {
        [fontPicker.navigationItem
            setTitleView:
                [objc_getClass("TFNTitleView")
                    titleViewWithTitle:[[BHTBundle sharedBundle]
                                           localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"]
                              subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title =
            [[BHTBundle sharedBundle] localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"];
    }
    [self.navigationController pushViewController:fontPicker animated:YES];
}

- (void)fontPickerViewControllerDidPickFont:(UIFontPickerViewController*)viewController {
    NSString* fontName =
        viewController.selectedFontDescriptor.fontAttributes[UIFontDescriptorNameAttribute];
    NSString* fontFamily =
        viewController.selectedFontDescriptor.fontAttributes[UIFontDescriptorFamilyAttribute];
    NSString* fontType = objc_getAssociatedObject(viewController, @"fontType");
    if ([fontType isEqualToString:@"bold"]) {
        [[NSUserDefaults standardUserDefaults] setObject:fontName forKey:@"bhtwitter_font_2"];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:fontFamily forKey:@"bhtwitter_font_1"];
    }
    [self updateVisibleToggles];
    [self.tableView reloadData];
    [viewController.navigationController popViewControllerAnimated:YES];
}

@end
