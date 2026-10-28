// X builds its Swift tab editor through T1TabCustomizationViewController.
// The Swift Save path reads the config's cached availability directly, so
// overriding only its Objective-C getter does not enable saving.

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdint.h>
#import <string.h>
#import "CustomTabBar/CustomTabBarUtility.h"
#import "CustomTabBar/NativeTabSelectionStore.h"

typedef void (*BHTRestoreTabIdentifiersFunction)(
    void* settings __attribute__((swift_context))) __attribute__((swiftcall));

static __thread BOOL BHTSavingNativeTabs = NO;
static __thread BOOL BHTRestoringNativeTabs = NO;

static NSString* BHTTabAccountID(id object) {
    if (![object respondsToSelector:@selector(accountID)]) {
        return nil;
    }
    id accountID = ((id (*)(id, SEL))objc_msgSend)(object, @selector(accountID));
    return [accountID isKindOfClass:NSString.class] ? accountID : nil;
}

static id BHTTabObjectField(id object, const char* name) {
    if (!object) {
        return nil;
    }
    Ivar field = class_getInstanceVariable(object_getClass(object), name);
    if (!field) {
        return nil;
    }
    ptrdiff_t offset = ivar_getOffset(field);
    size_t size = class_getInstanceSize(object_getClass(object));
    if (offset < (ptrdiff_t)sizeof(void*) ||
        (size_t)offset + sizeof(id) > size) {
        return nil;
    }
    // Swift's nested optional lazy reference uses 1 for "not initialized".
    // Reject that sentinel before ARC could attempt to retain it as an object.
    uintptr_t reference = 0;
    memcpy(&reference, (const unsigned char*)(__bridge void*)object + offset,
           sizeof(reference));
    if (reference < 4096 || reference % sizeof(void*) != 0) {
        return nil;
    }
    return object_getIvar(object, field);
}

static BOOL BHTEnableCachedTabCustomization(id config) {
    id helper = BHTTabObjectField(config, "migrationHelper");
    Class helperClass = NSClassFromString(@"_TtC14T1TwitterSwift33SubscriptionsInfraMigrationHelper");
    if (!helperClass || object_getClass(helper) != helperClass) {
        return NO;
    }
    id legacy = BHTTabObjectField(helper, "$__lazy_storage_$_legacyConfig");
    Class legacyClass = NSClassFromString(@"_TtC20TwitterSubscriptions31LegacySubscriptionFeatureConfig");
    if (!legacyClass || object_getClass(legacy) != legacyClass) {
        return NO;
    }
    Ivar enabled = class_getInstanceVariable(legacyClass, "isFeatureEnabled");
    Ivar claims = class_getInstanceVariable(legacyClass, "claims");
    if (!enabled || !claims) {
        return NO;
    }
    ptrdiff_t offset = ivar_getOffset(enabled);
    size_t size = class_getInstanceSize(legacyClass);
    if (offset < (ptrdiff_t)(2 * sizeof(void*)) ||
        (size_t)offset >= size || ivar_getOffset(claims) <= offset) {
        return NO;
    }
    // This is the one-byte Swift.Bool read by the native config getter. No
    // account claims or Swift reference/value storage are replaced.
    unsigned char value = 1;
    memcpy((unsigned char*)(__bridge void*)legacy + offset, &value, sizeof(value));
    return YES;
}

static id BHTPrepareNativeTabSave(id editor) {
    id model = BHTTabObjectField(editor, "viewModel");
    id settings = BHTTabObjectField(model, "navigationSettings");
    id config = BHTTabObjectField(settings, "$__lazy_storage_$_tabCustomizationConfig");
    if ([config respondsToSelector:@selector(isTabCustomizationEnabled)]) {
        // Calling the hooked ObjC getter primes and enables the cached config
        // that Swift's direct calls will subsequently read.
        BOOL enabled = ((BOOL (*)(id, SEL))objc_msgSend)(
            config, @selector(isTabCustomizationEnabled));
        if (enabled) {
            return settings;
        }
    }
    NSLog(@"[BHT] Native tab customization availability could not be enabled");
    return nil;
}

static void BHTRestoreNativeTabSelection(id controller) {
    id navigation = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(appNavigation));
    if (![navigation respondsToSelector:@selector(account)]) {
        return;
    }
    id account = ((id (*)(id, SEL))objc_msgSend)(navigation, @selector(account));
    NSString* accountID = BHTTabAccountID(account);
    if (accountID.length == 0) {
        return;
    }
    BHTRestoreTabIdentifiersFunction restore = (BHTRestoreTabIdentifiersFunction)dlsym(
        RTLD_DEFAULT,
        "$s14T1TwitterSwift25MainAppNavigationSettingsC21restoreTabIdentifiersyyF");
    if (!restore) {
        NSLog(@"[BHT] Native tab settings restore function was not found");
        return;
    }

    id editor = [CustomTabBarUtility editorForAccount:account];
    Class editorClass = NSClassFromString(@"T1TabCustomizationViewController");
    if (!editorClass || ![editor isKindOfClass:editorClass]) {
        return;
    }
    id settings = BHTPrepareNativeTabSave(editor);
    if (settings) {
        // Supply the explicitly saved blob even if startup already cleared X's
        // copy. Native code decodes it and publishes it to the glass controller.
        BOOL saved = BHTRestoringNativeTabs;
        BHTRestoringNativeTabs = YES;
        @try {
            restore((__bridge void*)settings);
        } @finally {
            BHTRestoringNativeTabs = saved;
        }
    }
}

%hook T1TabCustomizationConfig

- (BOOL)isTabCustomizationEnabled {
    BOOL enabled = %orig;
    if (enabled) {
        return YES;
    }
    if (BHTEnableCachedTabCustomization(self)) {
        return %orig;
    }
    return NO;
}

%end

%hook TFSAccountUserDefaults

- (void)setObject:(id)value forKey:(id)key {
    %orig;
    if (BHTSavingNativeTabs &&
        [BHTNativeTabSelectionStore isNativeTabSettingsKey:key]) {
        [[BHTNativeTabSelectionStore sharedStore]
                saveData:value
            forAccountID:BHTTabAccountID(self)
             settingsKey:key];
    }
}

- (id)objectForKey:(id)key {
    if ([BHTNativeTabSelectionStore isNativeTabSettingsKey:key] &&
        (BHTRestoringNativeTabs || [CustomTabBarUtility usesNativeEditor])) {
        NSData* saved = [[BHTNativeTabSelectionStore sharedStore]
            dataForAccountID:BHTTabAccountID(self)
                 settingsKey:key];
        if (saved) {
            return saved;
        }
    }
    return %orig;
}

%end

%hook _TtC14T1TwitterSwift34XTabbedAppNavigationViewController

- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(nfb_restoreNativeTabsAfterActivation:)
               name:UIApplicationDidBecomeActiveNotification
             object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidBecomeActiveNotification
                                                  object:nil];
    %orig;
}

%new
- (void)nfb_restoreNativeTabsAfterActivation:(NSNotification*)notification {
    id controller = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        BHTRestoreNativeTabSelection(controller);
    });
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    id controller = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        BHTRestoreNativeTabSelection(controller);
    });
}

%end

%hook T1TabCustomizationViewController

- (void)viewDidLoad {
    %orig;
    BHTPrepareNativeTabSave(self);
}

- (void)didPressSaveButton {
    BHTPrepareNativeTabSave(self);
    BOOL saved = BHTSavingNativeTabs;
    BHTSavingNativeTabs = [CustomTabBarUtility usesNativeEditor];
    @try {
        %orig;
    } @finally {
        BHTSavingNativeTabs = saved;
    }
}

%end
