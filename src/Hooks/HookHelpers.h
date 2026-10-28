//
//  BHTHookHelpers.h
//  NeoFreeBird
//
//  Shared imports and helpers for the hook files in src/Hooks.
//

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "CustomTabBar/CustomTabBarUtility.h"
#import "Download/DownloadInlineButton.h"
#import "Headers/TWHeaders.h"
#import "Headers/XHeaders.h"
#import "Padlock/AuthViewController.h"
#import "Settings/ModernSettingsViewController.h"
#import "ThemeColor/BHTDimPalette.h"
#import "ThemeColor/Palette.h"
#import "WebLogin/WebLoginViewController.h"

// Recursive view traversal (BHTHookHelpers.m)
void EnumerateSubviewsRecursively(UIView* view,
                                  void (^block)(UIView* currentView));

// TFNDataViewItem unwrapping for timeline section filtering (BHTHookHelpers.m)
id unwrapDataViewItem(id item);

// Module header/footer cleanup for timeline section filtering (BHTHookHelpers.m)
BOOL IsModuleHeaderItem(id item);
BOOL IsModuleFooterItem(id item);
void MarkEmptiedModuleChrome(NSArray* items, NSMutableIndexSet* removed);

// Live square-avatar restyling (Avatars.x)
void applySquareAvatarsSetting(void);

NSString* formatNumberWithSuffix(long long number);

bool NFBLiquidGlassEnabled(void);

// Custom theme color re-apply (Theme.x)
void applySelectedThemeColor(void);

// Dim recolor for the Swift-drawn immersive video controls (Theme.x)
void BHTApplyDimToVideoControls(UIView* controlsView);

// Long press on the home navigation bar opens NeoFreeBird settings (Settings.x)
void attachNeoFreeBirdSettingsGesture(UIViewController* home);

// Live pinned-tabs refresh when the hide setting is toggled (Timeline.x)
void applyHideCustomTimelinesSetting(void);

// Whether the account genuinely has a panel's tab, ignoring the forced tab
// gates (FeatureSwitches.x)
BOOL panelIsGenuinelyAvailable(long long panelID);

// Web session cookie harvesting (WebCreateTweet.x)
void prewarmWebCookiesIfNeeded(void);
void maybeHandleHarvestWebView(__unsafe_unretained id webViewController);
id accountForAuthenticatedWebView(void);

// Webview cookie login -> WebCreateTweet.x session (WebCreateTweet.x)
void webLoginDidCaptureCookies(NSString* userID, NSString* username,
                               NSDictionary<NSString*, NSString*>* cookiePairs);
BOOL isCookieLoginUserID(NSString* userID);

// Current web-session credentials (auth_token + ct0) for read-only web GraphQL
// requests such as restoring tweet source labels (WebCreateTweet.x)
NSDictionary* currentWebCredentials(void);

BOOL nfb_boolIvar(id object, const char* name, BOOL fallback);

void nfb_setBoolIvar(id object, const char* name, BOOL value);

id nfb_objectIvar(id object, const char* name);
