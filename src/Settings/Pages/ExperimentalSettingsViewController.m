//
//  ExperimentalSettingsViewController.m
//  NeoFreeBird
//
//  Created by orionblur
//

#import "Settings/Pages/ExperimentalSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"

@implementation ExperimentalSettingsViewController

- (NSString*)pageKey {
    return @"experimental";
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = objc_getAssociatedObject(sender, @"prefKey");
    if ([key isEqualToString:@"liquid_glass"]) {
        UIAlertController* alertController =
            [UIAlertController alertControllerWithTitle:[[BHTBundle sharedBundle]
                                                            localizedStringForKey:@"DIM_THEME_RESTART_ALERT_TITLE"]
                                                message:[[BHTBundle sharedBundle]
                                                            localizedStringForKey:@"LIQUID_GLASS_RESTART_ALERT_MESSAGE"]
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

@end
