#import "../HookHelpers.h"
#import "DownloadInlineButton.h"

static NSURL* nfbLastCapturedVoiceURL = nil;
static const void* kVoiceDownloadLongPressKey = &kVoiceDownloadLongPressKey;

void CaptureVoiceURL(NSURL* url, NSString* source);
void DownloadVoiceMessage(NSURL* sourceURL);
NSArray* DMVideoEntities(UIView* attachmentView);
UILongPressGestureRecognizer* VoiceDownloadLongPressRecognizer(UIView* view);
void SetVoiceDownloadLongPressRecognizer(UIView* view,
                                         UILongPressGestureRecognizer* recognizer);
