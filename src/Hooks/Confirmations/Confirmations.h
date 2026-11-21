#import <AVFoundation/AVFoundation.h>
#import "../HookHelpers.h"

static BOOL awaitingBlockAlert = NO;

BOOL UndoTweetEnabled(void);
BOOL FastBlockEnabled(void);
void PlayCustomSendSound(void);
void ShowConfirmation(void (^confirmed)(void));
