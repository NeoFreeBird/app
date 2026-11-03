#import "NativeTabSelectionStore.h"

static NSString* const BHTNativeSelectionsKey = @"bh_native_tab_selections";

@interface BHTNativeTabSelectionStore ()
@property (nonatomic, strong) NSUserDefaults* defaults;
@end

@implementation BHTNativeTabSelectionStore

+ (instancetype)sharedStore {
    static BHTNativeTabSelectionStore* store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[self alloc] initWithUserDefaults:NSUserDefaults.standardUserDefaults];
    });
    return store;
}

- (instancetype)initWithUserDefaults:(NSUserDefaults*)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults;
    }
    return self;
}

+ (BOOL)isNativeTabSettingsKey:(id)key {
    return [key isKindOfClass:NSString.class] &&
           [key hasPrefix:@"app-navigation-"] &&
           [key hasSuffix:@"-tab_identifiers"];
}

- (NSData*)dataForAccountID:(NSString*)accountID settingsKey:(NSString*)key {
    if (![accountID isKindOfClass:NSString.class] || accountID.length == 0 ||
        ![self.class isNativeTabSettingsKey:key]) {
        return nil;
    }
    @synchronized(self) {
        id selections = [self.defaults objectForKey:BHTNativeSelectionsKey];
        id account = [selections isKindOfClass:NSDictionary.class] ? selections[accountID] : nil;
        id data = [account isKindOfClass:NSDictionary.class] ? account[key] : nil;
        return [data isKindOfClass:NSData.class] ? data : nil;
    }
}

- (void)saveData:(NSData*)data forAccountID:(NSString*)accountID settingsKey:(NSString*)key {
    if (![accountID isKindOfClass:NSString.class] || accountID.length == 0 ||
        ![self.class isNativeTabSettingsKey:key] ||
        (data && ![data isKindOfClass:NSData.class])) {
        return;
    }
    @synchronized(self) {
        id saved = [self.defaults objectForKey:BHTNativeSelectionsKey];
        NSMutableDictionary* selections = [saved isKindOfClass:NSDictionary.class]
                                              ? [saved mutableCopy]
                                              : [NSMutableDictionary new];
        id savedAccount = selections[accountID];
        NSMutableDictionary* account = [savedAccount isKindOfClass:NSDictionary.class]
                                           ? [savedAccount mutableCopy]
                                           : [NSMutableDictionary new];
        if (data) {
            account[key] = [data copy];
        } else {
            [account removeObjectForKey:key];
        }
        if (account.count) {
            selections[accountID] = account;
        } else {
            [selections removeObjectForKey:accountID];
        }
        [self.defaults setObject:selections forKey:BHTNativeSelectionsKey];
    }
}

@end
