#import "WebCreateTweet.h"
#import "../HookHelpers.h"

// MARK: - Hooks

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionDataTask* task = %orig(outgoing);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(id)completionHandler {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionDataTask* task = %orig(outgoing, completionHandler);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request fromData:(NSData*)bodyData {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionUploadTask* task = %orig(outgoing, bodyData);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request fromFile:(NSURL*)fileURL {
    NSMutableURLRequest* outgoing = webRequestFromNativeSend(request);
    if (outgoing) {
        NSURLSessionUploadTask* task = %orig(outgoing, fileURL);
        watchCreateTweetTask(task, objc_getAssociatedObject(outgoing, WebPostingUIDKey));
        return task;
    }
    return %orig;
}

%end
