#import <Foundation/Foundation.h>

@class TFNTwitterStatus;

TFNTwitterStatus* statusFromObject(id object);
BOOL openAuthenticatedTweetWebView(NSString* statusID);
void showPostSentAlert(NSString* statusID);

extern const void* KeepReplyInWebViewKey;
extern const void* ReplyWebViewDismissingKey;
extern NSString* const ReplyCaptureScript;
extern NSString* const ReplyReadScript;
