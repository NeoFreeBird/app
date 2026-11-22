#import <CydiaSubstrate.h>
#import "../HookHelpers.h"

BOOL BlocksLinkTracking(void);
BOOL IsTalonURL(NSURL* url);
BOOL IsWebURL(NSURL* url);
NSString* TalonCacheKey(NSURL* url);
NSCache<NSString*, NSURL*>* KnownDestinations(void);
void RememberDestination(NSString* talonString, NSString* destinationString);
NSURL* WebLinksExpandedURLForStatus(id status, NSURL* url);
NSURL* DestinationForLink(NSURL* url, NSURL* expandedURL);
BOOL IsTrackingParameter(NSString* name, NSString* host);
NSURL* URLByStrippingTrackingParameters(NSURL* url);
BOOL ShouldKeepBrowserURLInApp(NSURL* url);
NSString* CleanedShareURLString(NSString* urlString);
NSString* CleanedCopiedTweetURL(NSString* urlString);
void (*OriginalPasteboardSetString)(id, SEL, NSString*);
void BHTPasteboardSetString(id pasteboard, SEL selector, NSString* string);
