#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

// Account/session access shared with login, app lifecycle and other web hooks.
void prewarmWebCookiesIfNeeded(void);
void maybeHandleHarvestWebView(__unsafe_unretained id webViewController);
id accountForAuthenticatedWebView(void);
void webLoginDidCaptureCookies(NSString* userID, NSString* username,
                               NSDictionary<NSString*, NSString*>* cookiePairs);
BOOL isCookieLoginUserID(NSString* userID);
NSDictionary* currentWebCredentials(void);

// Cookie-login webview hooks. A nil prepared request is queued until seeding ends.
NSDictionary* BHTCachedWebSessionForAccount(id account);
void BHTRememberWebViewSession(id controller, NSDictionary* session);
void BHTCaptureWebViewSession(id controller, id account);
void BHTSeedCookieLoginConfiguration(id controller, id configuration, id result);
NSURLRequest* BHTPrepareCookieLoginLoad(WKWebView* webView, NSURLRequest* request);

// Network hooks. A nil rewritten request means the native request is left alone.
NSMutableURLRequest* BHTWebRequestFromNativeSend(NSURLRequest* request);
void BHTPrepareWebTaskForResume(NSURLSessionTask* task);
void BHTWatchCreateTweetTask(id task, NSURLRequest* request);
