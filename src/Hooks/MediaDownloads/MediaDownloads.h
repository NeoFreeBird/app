#import "../HookHelpers.h"
#import "DownloadInlineButton.h"

static NSURL* nfbLastCapturedVoiceURL;
static const void* kVoiceDownloadLongPressKey = &kVoiceDownloadLongPressKey;

void CaptureVoiceURL(NSURL* url, NSString* source);
void DownloadVoiceMessage(NSURL* sourceURL);
UILongPressGestureRecognizer* VoiceDownloadLongPressRecognizer(UIView* view);
void SetVoiceDownloadLongPressRecognizer(UIView* view,
                                         UILongPressGestureRecognizer* recognizer);
