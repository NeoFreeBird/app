#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Stores X's already-encoded selection without interpreting Swift tab values.
@interface BHTNativeTabSelectionStore : NSObject
+ (instancetype)sharedStore;
- (instancetype)initWithUserDefaults:(NSUserDefaults*)defaults;
+ (BOOL)isNativeTabSettingsKey:(id)key;
- (nullable NSData*)dataForAccountID:(NSString*)accountID settingsKey:(NSString*)key;
// nil is X's explicit save of its default layout, and clears the saved copy.
- (void)saveData:(nullable NSData*)data forAccountID:(NSString*)accountID settingsKey:(NSString*)key;
@end

NS_ASSUME_NONNULL_END
