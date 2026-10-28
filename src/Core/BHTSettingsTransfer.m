//
//  BHTSettingsTransfer.m
//  NeoFreeBird
//
//  Created by orionblur
//

#import "Core/BHTSettingsTransfer.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/Helpers.h"

NSString* const BHTSettingsTransferErrorDomain = @"com.neofreebird.settings-transfer";

// Envelope around the settings themselves, so a JSON file picked by mistake is
// rejected with a message rather than half-applied.
static NSString* const kFormatKey = @"format";
static NSString* const kFormatValue = @"neofreebird-settings";
static NSString* const kFormatVersionKey = @"formatVersion";
static NSString* const kExportedByKey = @"exportedBy";
static NSString* const kExportedAtKey = @"exportedAt";
static NSString* const kSettingsKey = @"settings";

static const NSInteger kFormatVersion = 1;

// Preferences owned outside the settings registry. The accent colour is also
// mirrored into Twitter's own key, but that is done on apply rather than
// carried in the file.
static NSString* const kAccentColorKey = @"bh_color_theme_selectedColor";
static NSString* const kVisibleTabsKey = @"bh_tabs_visible";
// Kept in step with AppIconViewController, which trusts this key over
// UIApplication's stale alternateIconName on sideloaded installs.
static NSString* const kAppIconKey = @"bh_last_selected_app_icon";
static NSString* const kPrimaryIconSentinel = @"PrimaryIcon";

static NSArray* skippedKeys = @[@"custom_send_sound_name"];

// The tab registry (every tab seen on this device) is deliberately absent: it
// is captured metadata, not a choice, and is rebuilt on launch.
static NSDictionary<NSString*, Class>* BHTExtraTransferableKeys(void) {
    static NSDictionary<NSString*, Class>* keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @{
            kAccentColorKey: [NSNumber class],
            kVisibleTabsKey: [NSArray class],
            kAppIconKey: [NSString class]
        };
    });
    return keys;
}

// A registry row's type follows its default; the rows without one store the
// text shown as their subtitle.
static NSDictionary<NSString*, Class>* BHTTransferableKeyClasses(void) {
    static NSDictionary<NSString*, Class>* classes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString*, Class>* map = [NSMutableDictionary dictionary];
        for (NSString* key in [BHTSettings allPreferenceKeys]) {
            if (![skippedKeys containsObject:key]) {
                id defaultValue = [BHTSettings settingForKey:key][@"default"];
                map[key] = [defaultValue isKindOfClass:[NSNumber class]] ? [NSNumber class]
                                                                         : [NSString class];
            }
        }
        [map addEntriesFromDictionary:BHTExtraTransferableKeys()];
        classes = [map copy];
    });
    return classes;
}

// Guards against a hand-edited file: a string where a switch belongs would be
// read back as a truthy value forever after.
static BOOL BHTValueMatchesClass(id value, Class expected) {
    if (![value isKindOfClass:expected]) {
        return NO;
    }
    if (expected == [NSArray class]) {
        for (id element in (NSArray*)value) {
            if (![element isKindOfClass:[NSString class]]) {
                return NO;
            }
        }
    }
    return YES;
}

static NSError* BHTTransferError(BHTSettingsTransferErrorCode code, NSString* messageKey) {
    NSString* message = [[BHTBundle sharedBundle] localizedStringForKey:messageKey];
    return [NSError errorWithDomain:BHTSettingsTransferErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation BHTSettingsTransfer

#pragma mark - Export

+ (NSArray<NSString*>*)transferableKeys {
    return BHTTransferableKeyClasses().allKeys;
}

+ (NSDictionary*)currentSettings {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary* settings = [NSMutableDictionary dictionary];
    [BHTTransferableKeyClasses()
        enumerateKeysAndObjectsUsingBlock:^(NSString* key, Class expected, BOOL* stop) {
            // A switch the user never touched still has a defined value, and
            // writing it out keeps the import deterministic. Text and list
            // preferences have no default worth recording.
            id value = [defaults objectForKey:key] ?: [BHTSettings settingForKey:key][@"default"];
            if (value && BHTValueMatchesClass(value, expected)) {
                settings[key] = value;
            }
        }];
    return [settings copy];
}

+ (NSDictionary*)exportPayload {
    NSISO8601DateFormatter* formatter = [[NSISO8601DateFormatter alloc] init];
    return @{
        kFormatKey: kFormatValue,
        kFormatVersionKey: @(kFormatVersion),
        kExportedByKey: @NFB_VERSION_STRING,
        kExportedAtKey: [formatter stringFromDate:[NSDate date]],
        kSettingsKey: [self currentSettings]
    };
}

+ (NSString*)exportFileName {
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [NSString stringWithFormat:@"NeoFreeBird-Settings-%@.json",
                                      [formatter stringFromDate:[NSDate date]]];
}

+ (NSURL*)writeExportToTemporaryDirectory:(NSError**)error {
    NSError* serializationError = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:[self exportPayload]
                                                   options:NSJSONWritingPrettyPrinted |
                                                           NSJSONWritingSortedKeys
                                                     error:&serializationError];
    if (!data) {
        if (error) {
            *error = BHTTransferError(BHTSettingsTransferErrorWriteFailed,
                                      @"SETTINGS_EXPORT_WRITE_FAILED");
        }
        return nil;
    }

    // A fresh directory per export keeps the file name intact even while an
    // earlier picker still holds the previous one.
    NSURL* directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSUUID UUID].UUIDString
                        isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil]) {
        if (error) {
            *error = BHTTransferError(BHTSettingsTransferErrorWriteFailed,
                                      @"SETTINGS_EXPORT_WRITE_FAILED");
        }
        return nil;
    }

    NSURL* fileURL = [directory URLByAppendingPathComponent:[self exportFileName]];
    if (![data writeToURL:fileURL options:NSDataWritingAtomic error:nil]) {
        if (error) {
            *error = BHTTransferError(BHTSettingsTransferErrorWriteFailed,
                                      @"SETTINGS_EXPORT_WRITE_FAILED");
        }
        return nil;
    }
    return fileURL;
}

#pragma mark - Import

+ (NSInteger)importSettingsFromFileAtURL:(NSURL*)url error:(NSError**)error {
    // Files handed over by the document picker live outside our sandbox until
    // the copy is made.
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData* data = [NSData dataWithContentsOfURL:url];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }
    if (!data) {
        if (error) {
            *error = BHTTransferError(BHTSettingsTransferErrorUnreadableFile,
                                      @"SETTINGS_TRANSFER_UNREADABLE_FILE");
        }
        return -1;
    }

    id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![payload isKindOfClass:[NSDictionary class]] ||
        ![payload[kFormatKey] isEqual:kFormatValue] ||
        ![payload[kSettingsKey] isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = BHTTransferError(BHTSettingsTransferErrorMalformedFile,
                                      @"SETTINGS_TRANSFER_MALFORMED_FILE");
        }
        return -1;
    }

    NSDictionary* imported = payload[kSettingsKey];
    NSDictionary<NSString*, Class>* expectedClasses = BHTTransferableKeyClasses();
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray<NSString*>* applied = [NSMutableArray array];

    [imported enumerateKeysAndObjectsUsingBlock:^(NSString* key, id value, BOOL* stop) {
        Class expected = expectedClasses[key];
        // Unknown keys are skipped rather than written through: an export from a
        // newer build should still import everything this one understands.
        if (!expected || ![key isKindOfClass:[NSString class]] ||
            !BHTValueMatchesClass(value, expected)) {
            return;
        }
        [defaults setObject:value forKey:key];
        [applied addObject:key];
    }];

    if (applied.count == 0) {
        if (error) {
            *error = BHTTransferError(BHTSettingsTransferErrorNoRecognisedSettings,
                                      @"SETTINGS_TRANSFER_NO_SETTINGS");
        }
        return -1;
    }

    [defaults synchronize];
    [self applySideEffectsForImportedKeys:applied];
    return (NSInteger)applied.count;
}

// Most preferences are read straight from NSUserDefaults on use, but the accent
// colour and the app icon are held elsewhere as well and have to be pushed.
+ (void)applySideEffectsForImportedKeys:(NSArray<NSString*>*)keys {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    if ([keys containsObject:kAccentColorKey]) {
        changeTwitterColor([defaults integerForKey:kAccentColorKey]);
    }

    if ([keys containsObject:kAppIconKey] &&
        [UIApplication sharedApplication].supportsAlternateIcons) {
        NSString* iconName = [defaults stringForKey:kAppIconKey];
        NSString* toSet = [iconName isEqualToString:kPrimaryIconSentinel] ? nil : iconName;
        [[UIApplication sharedApplication] setAlternateIconName:toSet
                                              completionHandler:^(NSError* error){}];
    }
}

+ (void)resetAllSettings {
    // Go through BHTSettings to reset all settings to their default values
    for (NSString* key in [BHTSettings allPreferenceKeys]) {
        id defaultValue = [BHTSettings settingForKey:key][@"default"];
        if (defaultValue) {
            [[NSUserDefaults standardUserDefaults] setObject:defaultValue forKey:key];
        } else {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
        }
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self applySideEffectsForImportedKeys:[BHTSettingsTransfer transferableKeys]];
}

@end
