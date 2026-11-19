#import "../HookHelpers.h"
#import "WebCreateTweet.h"

extern NSString* const BHTWebSessionUserAgent;

// Module-private interfaces: session state and its locks stay in WebSession.m.
BOOL BHTNativeCreateTweetInterceptEnabled(void);
void BHTStoreWebCookies(NSArray<NSHTTPCookie*>* cookies);
void BHTHarvestSharedCookies(void);
NSDictionary* BHTCurrentWebSessionCookies(void);
NSString* BHTCurrentWebUserID(void);
BOOL BHTResolveWebCredentials(NSString* userID, NSString** authToken, NSString** ct0);
void BHTInvalidateWebCredentials(NSString* userID, NSURLRequest* request);
void BHTUpdateCreateTweetQueryID(NSString* queryID);
NSString* BHTCreateTweetPath(void);
NSString* BHTCreateNoteTweetPath(void);

void BHTRefreshWebCookiesViaWebView(void);
void BHTSeedWebSessionCookies(WKHTTPCookieStore* store,
                              NSDictionary<NSString*, NSString*>* pairs,
                              void (^done)(void));
NSString* BHTTransactionIDForRequest(NSURLRequest* request);
