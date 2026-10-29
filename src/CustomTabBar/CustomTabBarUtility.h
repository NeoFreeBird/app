//
//  CustomTabBarUtility.h
//  NeoFreeBird
//
//  Created by Bandar Alruwaili on 10/12/2023.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// pageID of the Home tab, which is always kept visible and pinned first.
extern NSString* const CustomTabBarHomePageID;

// Registry keys for a captured tab's metadata.
extern NSString* const TabPageKey; // scribePage identifier
extern NSString* const
    TabTitleKey;                      // display title (already localised by the app)
extern NSString* const TabImageKey;   // vector image name
extern NSString* const TabPanelIDKey; // T1 panel ID (NSNumber)

@interface CustomTabBarUtility : NSObject

+ (BOOL)usesNativeEditor;
+ (nullable UIViewController*)editorForAccount:(nullable id)account;

// Records the tabs the app builds so the editor can display real titles and
// icons without hardcoding them. Called from the tab bar hook with the live tab
// views.
+ (void)recordTabViews:(NSArray*)tabViews;

// Every tab the app has built this session (or last session), in the order
// seen.
+ (NSArray<NSDictionary*>*)availableTabs;

// Metadata for a single tab, or nil if it has never been seen.
+ (nullable NSDictionary*)metadataForPage:(NSString*)pageID;

// The visible tabs in the user's chosen order (Home first). Returns nil when
// the user has never customised the bar, so callers can fall back to the
// default.
+ (nullable NSArray<NSString*>*)visiblePageIDsInOrder;

// Persists the editor's selection; every other tab is hidden.
+ (void)setVisiblePageIDs:(NSArray<NSString*>*)visible;

// Clears the user's selection, reverting to the default layout.
+ (void)resetSelection;

// The tabs shown until the user customises the bar: Home, Search, Notifications
// and Chats. Everything else the app offers is available in the editor but
// hidden.
+ (NSArray<NSString*>*)defaultVisiblePageIDs;

@end

NS_ASSUME_NONNULL_END
