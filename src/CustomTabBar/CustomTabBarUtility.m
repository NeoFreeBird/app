//
//  CustomTabBarUtility.m
//  NeoFreeBird
//
//  Created by Bandar Alruwaili on 10/12/2023.
//

#import "CustomTabBarUtility.h"
#import <objc/message.h>
#import "Core/BHTSettings.h"
#import "CustomTabBarViewController.h"
#import "Headers/T1Headers.h"

@protocol BHTNativeTabCustomizationInitializing <NSObject>
- (instancetype)initWithAccount:(id)account scribeContext:(id)context;
@end

// The Home tab is the app's landing surface, so it is always kept visible,
// pinned first, and can never end up in the hidden list.
NSString* const CustomTabBarHomePageID = @"home";
NSString* const CustomTabBarMorePageID = @"dash";

NSString* const TabPageKey = @"page";
NSString* const TabTitleKey = @"title";
NSString* const TabImageKey = @"image";
NSString* const TabPanelIDKey = @"panelID";

static NSString* const kVisibleKey = @"bh_tabs_visible";
static NSString* const kRegistryKey = @"bh_tab_registry";

// Selection list retired when hiding became implicit (not in the visible list =
// hidden); removed on sight so old installs don't keep stale data around.
static NSString* const kLegacyHiddenKey = @"bh_tabs_hidden";

@implementation CustomTabBarUtility

#pragma mark - Editor routing

+ (BOOL)usesNativeEditor {
    id host = [NSClassFromString(@"T1HostViewController") sharedHostViewController];
    if ([host respondsToSelector:@selector(appNavigation)]) {
        id navigation = ((id (*)(id, SEL))objc_msgSend)(host, @selector(appNavigation));
        if (navigation) {
            Class routerClass = NSClassFromString(@"_TtC14T1TwitterSwift20XTabbedAppNavigation");
            return routerClass && [navigation isKindOfClass:routerClass];
        }
    }
    return [BHTSettings boolForKey:@"liquid_glass"];
}

+ (UIViewController*)editorForAccount:(id)account {
    if (![self usesNativeEditor]) {
        return [[CustomTabBarViewController alloc] init];
    }

    Class editorClass = NSClassFromString(@"T1TabCustomizationViewController");
    Class contextClass = NSClassFromString(@"TFSTwitterScribeContext");
    SEL contextSelector = @selector(scribeContextWithPage:);
    if (![editorClass isSubclassOfClass:[UIViewController class]] ||
        ![editorClass instancesRespondToSelector:@selector(initWithAccount:scribeContext:)] ||
        ![contextClass respondsToSelector:contextSelector]) {
        return nil;
    }

    if (!account) {
        id host = [NSClassFromString(@"T1HostViewController") sharedHostViewController];
        account = [host currentAccount];
    }
    if (!account) {
        return nil;
    }

    id context = ((id (*)(id, SEL, id))objc_msgSend)(
        contextClass, contextSelector, @"settings");
    if (!context) {
        return nil;
    }

    return (UIViewController*)[(id<BHTNativeTabCustomizationInitializing>)[editorClass alloc]
        initWithAccount:account
          scribeContext:context];
}

#pragma mark - Live capture

// Ordered union of every tab seen this session, so a tab that briefly drops out
// of a tab bar update isn't forgotten while the editor is open.
+ (NSMutableArray<NSDictionary*>*)registry {
    static NSMutableArray<NSDictionary*>* registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSMutableArray array];
        NSArray* saved =
            [[NSUserDefaults standardUserDefaults] arrayForKey:kRegistryKey];
        if (saved) {
            [registry addObjectsFromArray:saved];
        }
    });
    return registry;
}

+ (void)recordTabViews:(NSArray*)tabViews {
    NSMutableArray<NSDictionary*>* registry = [self registry];
    BOOL changed = NO;

    for (T1TabView* tabView in tabViews) {
        NSString* page = tabView.scribePage;
        if (page.length == 0) {
            continue;
        }

        NSString* title = tabView.title.length ? tabView.title : page;
        NSString* image = tabView.imageName ?: @"";
        if (image.length == 0) {
            // Avatar-drawn tabs (Profile) have no imageName; use the glyph the
            // native customization screen resolves for the panel.
            image = [NSClassFromString(@"T1PanelIdentity")
                        iconImageNameForPanelID:tabView.panelID]
                        ?: @"";
        }
        NSDictionary* entry = @{
            TabPageKey: page,
            TabTitleKey: title,
            TabImageKey: image,
            TabPanelIDKey: @(tabView.panelID)
        };

        NSInteger existing = NSNotFound;
        for (NSInteger i = 0; i < (NSInteger)registry.count; i++) {
            if ([registry[i][TabPageKey] isEqualToString:page]) {
                existing = i;
                break;
            }
        }

        if (existing == NSNotFound) {
            [registry addObject:entry];
            changed = YES;
        } else if (![registry[existing] isEqualToDictionary:entry]) {
            registry[existing] = entry;
            changed = YES;
        }
    }

    if (changed) {
        [[NSUserDefaults standardUserDefaults] setObject:[registry copy]
                                                  forKey:kRegistryKey];
    }
}

+ (NSArray<NSDictionary*>*)availableTabs {
    return [[self registry] copy];
}

+ (NSDictionary*)metadataForPage:(NSString*)pageID {
    for (NSDictionary* entry in [self registry]) {
        if ([entry[TabPageKey] isEqualToString:pageID]) {
            return entry;
        }
    }
    return nil;
}

#pragma mark - Selection

+ (NSArray<NSString*>*)visiblePageIDsInOrder {
    NSArray<NSString*>* visible =
        [[NSUserDefaults standardUserDefaults] stringArrayForKey:kVisibleKey];
    if (!visible) {
        return nil;
    }

    NSMutableArray<NSString*>* pageIDs = [visible mutableCopy];
    // Home is always visible and always first.
    [pageIDs removeObject:CustomTabBarHomePageID];
    [pageIDs insertObject:CustomTabBarHomePageID atIndex:0];
    [pageIDs removeObject:CustomTabBarMorePageID];
    [pageIDs addObject:CustomTabBarMorePageID];
    return pageIDs;
}

+ (void)setVisiblePageIDs:(NSArray<NSString*>*)visible {
    [[NSUserDefaults standardUserDefaults] setObject:visible forKey:kVisibleKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLegacyHiddenKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)resetSelection {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kVisibleKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLegacyHiddenKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSArray<NSString*>*)defaultVisiblePageIDs {
    return @[@"home", @"guide", @"ntab", @"messages", @"dash"];
}

@end
