//
//  PresetsSettingsViewController.m
//  NeoFreeBird
//
//  Created by orionblur
//

#import "Settings/Pages/PresetsSettingsViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/BHTBundle.h"
#import "Core/BHTSettingsTransfer.h"
#import "Headers/TWHeaders.h"

// The picker's own mode property is deprecated, so the purpose is tagged on the
// controller instead and read back in the shared delegate callback.
static char kPickerPurposeKey;
static NSString* const kPickerPurposeImport = @"import";

@interface PresetsSettingsViewController () <UIDocumentPickerDelegate>
@end

@implementation PresetsSettingsViewController

- (NSString*)pageKey {
    return @"presets";
}

#pragma mark - Alerts

- (void)showAlertWithTitleKey:(NSString*)titleKey message:(NSString*)message {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:titleKey]
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                        localizedStringForKey:@"OK_ACTION_LABEL"]
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Export

- (void)exportSettings:(NSDictionary*)sender {
    NSError* error = nil;
    NSURL* fileURL = [BHTSettingsTransfer writeExportToTemporaryDirectory:&error];
    if (!fileURL) {
        [self showAlertWithTitleKey:@"SETTINGS_EXPORT_FAILED_TITLE"
                            message:error.localizedDescription];
        return;
    }

    UIDocumentPickerViewController* picker =
        [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL]
                                                              asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Import

// Importing replaces every setting the file names, so it is worth a confirm
// before the file browser takes over the screen.
- (void)importSettings:(NSDictionary*)sender {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"SETTINGS_IMPORT_CONFIRM_TITLE"]
                         message:[bundle localizedStringForKey:@"SETTINGS_IMPORT_CONFIRM_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle
                                                        localizedStringForKey:@"CANCEL_ACTION_LABEL"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[bundle
                                             localizedStringForKey:@"SETTINGS_IMPORT_CONFIRM_BUTTON"]
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction* action) {
                                     [self presentImportPicker];
                                 }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSettings:(NSDictionary*)sender {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"SETTINGS_RESET_CONFIRM_TITLE"]
                         message:[bundle localizedStringForKey:@"SETTINGS_RESET_CONFIRM_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle
                                                        localizedStringForKey:@"CANCEL_ACTION_LABEL"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[bundle
                                             localizedStringForKey:@"SETTINGS_RESET_CONFIRM_BUTTON"]
                                   style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction* action) {
                                     [BHTSettingsTransfer resetAllSettings];
                                     [self updateVisibleToggles];
                                     [self.tableView reloadData];
                                     [self presentResetRestartPrompt];
                                 }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentResetRestartPrompt {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"SETTINGS_RESET_SUCCESS_TITLE"]
                         message:[bundle localizedStringForKey:@"SETTINGS_RESET_SUCCESS_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle
                                                        localizedStringForKey:@"SETTINGS_IMPORT_LATER_BUTTON"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle
                                                        localizedStringForKey:@"SETTINGS_IMPORT_RESTART_BUTTON"]
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction* action) {
                                                exit(0);
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentImportPicker {
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeJSON]
                            asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    objc_setAssociatedObject(picker, &kPickerPurposeKey, kPickerPurposeImport,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)applyImportFromURL:(NSURL*)url {
    NSError* error = nil;
    NSInteger applied = [BHTSettingsTransfer importSettingsFromFileAtURL:url error:&error];
    if (applied < 0) {
        [self showAlertWithTitleKey:@"SETTINGS_IMPORT_FAILED_TITLE"
                            message:error.localizedDescription];
        return;
    }

    // Rows on this page never change, but the imported values have to be live
    // for whichever page the user opens next.
    [self updateVisibleToggles];
    [self.tableView reloadData];

    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSString* format = [bundle localizedStringForKey:@"SETTINGS_IMPORT_SUCCESS_MESSAGE"];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"SETTINGS_IMPORT_SUCCESS_TITLE"]
                         message:[NSString stringWithFormat:format, (long)applied]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:
                                                                @"SETTINGS_IMPORT_LATER_BUTTON"]
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:
                                                                @"SETTINGS_IMPORT_RESTART_BUTTON"]
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction* action) {
                                                exit(0);
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Document Picker

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    NSString* purpose = objc_getAssociatedObject(controller, &kPickerPurposeKey);
    // An export reports the location it saved to, which there is nothing to do
    // with.
    if (![purpose isEqualToString:kPickerPurposeImport] || urls.firstObject == nil) {
        return;
    }
    [self applyImportFromURL:urls.firstObject];
}

@end
