//
//  BHTSettingsTransfer.h
//  NeoFreeBird
//
//  Created by orionblur
//

#import <Foundation/Foundation.h>

extern NSString* const BHTSettingsTransferErrorDomain;

typedef NS_ENUM(NSInteger, BHTSettingsTransferErrorCode) {
    BHTSettingsTransferErrorUnreadableFile = 1,
    BHTSettingsTransferErrorMalformedFile,
    BHTSettingsTransferErrorNoRecognisedSettings,
    BHTSettingsTransferErrorWriteFailed
};

// Moves the tweak's preferences in and out of a plain JSON file, so a setup can
// be backed up before a reinstall or carried over to another device.
@interface BHTSettingsTransfer : NSObject

// Every preference an export carries: the registry's own keys plus the handful
// stored outside it (accent colour, tab bar layout, app icon).
+ (NSArray<NSString*>*)transferableKeys;

// The settings an export would write out right now, keyed by preference name.
+ (NSDictionary*)currentSettings;

// Writes an export to the temporary directory and returns its URL, or nil with
// `error` set. The caller hands the URL to a document picker; the picker copies
// it, so the temporary file can be left to the system.
+ (NSURL*)writeExportToTemporaryDirectory:(NSError**)error;

// Applies the settings in the file at `url`, skipping anything this version
// does not recognise, and returns how many were applied — or -1 with `error`
// set when the file could not be read or was not one of our exports.
+ (NSInteger)importSettingsFromFileAtURL:(NSURL*)url error:(NSError**)error;

// Restores every registered preference to its default and reapplies settings
// whose values are also cached outside NSUserDefaults.
+ (void)resetAllSettings;

@end
