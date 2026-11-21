#import "WebCreateTweet.h"
#import "../HookHelpers.h"

%hook T1WebViewController
- (id)initWithRootURL:(NSURL*)rootURL
                      account:(id)account
           shouldAuthenticate:(BOOL)shouldAuthenticate
    shouldPresentAsNativePage:(BOOL)shouldPresentAsNativePage
                 sourceStatus:(id)sourceStatus
              scribeComponent:(id)scribeComponent
             scribeParameters:(id)scribeParameters {
    NSDictionary* session = shouldAuthenticate ? BHTCachedWebSessionForAccount(account) : nil;
    if (!session) {
        return %orig;
    }

    self = %orig(rootURL, account, NO, shouldPresentAsNativePage, sourceStatus, scribeComponent,
                     scribeParameters);
    if (self) {
        BHTRememberWebViewSession(self, session);
    }
    return self;
}

// Every web view goes through here, store web cookies so that we don't have a miss
- (void)_t1_sharedInitWithRootURL:(id)rootURL
                          account:(id)account
                     sourceStatus:(id)sourceStatus
                  scribeComponent:(id)scribeComponent
                 scribeParameters:(id)scribeParameters {
    %orig;
    BHTCaptureWebViewSession(self, account);
}

// Called from -loadView with the configuration the webview is about to be created with.
- (id)updateConfiguration:(id)configuration {
    id result = %orig;
    BHTSeedCookieLoginConfiguration(self, configuration, result);
    return result;
}

%end

%hook _TtC14T1TwitterSwift26PreloadedWebviewController
- (id)updateConfiguration:(id)configuration {
    id result = %orig;
    BHTSeedCookieLoginConfiguration(self, configuration, result);
    return result;
}
%end

%hook WKWebView
- (WKNavigation*)loadRequest:(NSURLRequest*)request {
    NSURLRequest* effective = BHTPrepareCookieLoginLoad(self, request);
    return effective ? %orig(effective) : nil;
}
%end

%hook NSURLSessionTask
- (void)resume {
    BHTPrepareWebTaskForResume(self);
    %orig;
}
%end

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request {
    NSMutableURLRequest* outgoing = BHTWebRequestFromNativeSend(request);
    NSURLSessionDataTask* task = %orig(outgoing ?: request);
    BHTWatchCreateTweetTask(task, outgoing);
    return task;
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(id)completionHandler {
    NSMutableURLRequest* outgoing = BHTWebRequestFromNativeSend(request);
    NSURLSessionDataTask* task = %orig(outgoing ?: request, completionHandler);
    BHTWatchCreateTweetTask(task, outgoing);
    return task;
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                                    delegate:(id)delegate {
    NSMutableURLRequest* outgoing = BHTWebRequestFromNativeSend(request);
    NSURLSessionDataTask* task = %orig(outgoing ?: request, delegate);
    BHTWatchCreateTweetTask(task, outgoing);
    return task;
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                                    delegate:(id)delegate
                               delegateQueue:(NSOperationQueue*)delegateQueue {
    NSMutableURLRequest* outgoing = BHTWebRequestFromNativeSend(request);
    NSURLSessionDataTask* task = %orig(outgoing ?: request, delegate, delegateQueue);
    BHTWatchCreateTweetTask(task, outgoing);
    return task;
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request fromData:(NSData*)bodyData {
    NSMutableURLRequest* outgoing = BHTWebRequestFromNativeSend(request);
    NSURLSessionUploadTask* task = %orig(outgoing ?: request, bodyData);
    BHTWatchCreateTweetTask(task, outgoing);
    return task;
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request fromFile:(NSURL*)fileURL {
    NSMutableURLRequest* outgoing = BHTWebRequestFromNativeSend(request);
    NSURLSessionUploadTask* task = %orig(outgoing ?: request, fileURL);
    BHTWatchCreateTweetTask(task, outgoing);
    return task;
}

- (NSURLSessionUploadTask*)uploadTaskWithStreamedRequest:(NSURLRequest*)request {
    NSMutableURLRequest* outgoing = BHTWebRequestFromNativeSend(request);
    NSURLSessionUploadTask* task = %orig(outgoing ?: request);
    BHTWatchCreateTweetTask(task, outgoing);
    return task;
}

%end
