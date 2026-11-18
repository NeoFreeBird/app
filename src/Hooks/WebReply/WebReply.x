#import "WebReply.h"

%hook T1StatusViewInlineActionTapEventHandler
- (void)performReplyActionWithAccount:(__unsafe_unretained id)account
                                event:(__unsafe_unretained id)event
                           controller:(__unsafe_unretained id)controller
                        scribeContext:(__unsafe_unretained id)scribeContext
                        scribeElement:(__unsafe_unretained id)scribeElement
                           parameters:(__unsafe_unretained id)parameters
                       originalStatus:(__unsafe_unretained TFNTwitterStatus*)originalStatus {
    if (![BHTSettings boolForKey:@"reply_in_webview"]) {
        return %orig;
    }

    if (![originalStatus respondsToSelector:@selector(statusID)]) {
        return %orig;
    }

    NSInteger statusID = originalStatus.statusID;
    if (statusID <= 0) {
        return %orig;
    }

    NSString* statusIDString = @(statusID).stringValue;
    if (!openAuthenticatedTweetWebView(statusIDString)) {
        return %orig;
    }
}
%end

%hook T1PersistentComposeViewController
- (void)persistentComposeViewDidTap:(id)composeView {
    if (![BHTSettings boolForKey:@"reply_in_webview"]) {
        return %orig;
    }

    TFNTwitterStatus* status = statusFromObject(self.statusViewModel);
    NSInteger statusID = status.statusID;
    if (statusID <= 0) {
        return %orig;
    }

    NSString* statusIDString = @(statusID).stringValue;
    if (!openAuthenticatedTweetWebView(statusIDString)) {
        return %orig;
    }
}
%end

%hook T1WebViewController
- (void)didFinishLoadingWithError:(id)error {
    %orig;

    maybeHandleHarvestWebView(self);

    if (!objc_getAssociatedObject(self, KeepReplyInWebViewKey)) {
        return;
    }

    WKWebView* webView = [self webView];
    if ([webView isKindOfClass:%c(WKWebView)]) {
        [webView evaluateJavaScript:ReplyCaptureScript completionHandler:nil];
    }
}

- (BOOL)doesURLResultTypeOpenInWebview:(long long)resultType {
    if (objc_getAssociatedObject(self, KeepReplyInWebViewKey)) {
        return YES;
    }
    return %orig;
}

- (void)setCurrentURL:(NSURL*)url {
    %orig;

    if (!objc_getAssociatedObject(self, KeepReplyInWebViewKey) ||
        ![url.path isEqualToString:@"/home"]) {
        return;
    }

    // setCurrentURL: can fire more than once for the same navigation; only act once.
    if (objc_getAssociatedObject(self, ReplyWebViewDismissingKey)) {
        return;
    }
    objc_setAssociatedObject(self, ReplyWebViewDismissingKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak T1WebViewController* weakSelf = self;

    void (^finish)(NSString*) = ^(NSString* newReplyID) {
        [weakSelf dismissViewControllerAnimated:YES
                                     completion:^{
                                         if (newReplyID.length > 0) {
                                             showPostSentAlert(newReplyID);
                                         }
                                     }];
    };

    WKWebView* webView = [self webView];
    if ([webView isKindOfClass:%c(WKWebView)]) {
        [webView evaluateJavaScript:ReplyReadScript
                  completionHandler:^(id result, NSError* jsError) {
                      NSString* newReplyID =
                          [result isKindOfClass:[NSString class]] ? (NSString*)result : nil;
                      finish(newReplyID);
                  }];
    } else {
        finish(nil);
    }
}
%end
