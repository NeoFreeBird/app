#import <Foundation/Foundation.h>

// Shared by the lifecycle, reply, and location-label modules.
void prewarmWebCookiesIfNeeded(void);
void maybeHandleHarvestWebView(__unsafe_unretained id webViewController);
id accountForAuthenticatedWebView(void);
NSDictionary* currentWebCredentials(void);

NSMutableURLRequest* webRequestFromNativeSend(NSURLRequest* request);
void watchCreateTweetTask(id task, NSString* userID);

extern const void* WebPostingUIDKey;
