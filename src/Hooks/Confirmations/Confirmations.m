#import "Confirmations.h"

// A timeout of 0 disables undo; any positive value is the delay in seconds.
BOOL UndoTweetEnabled(void) {
    return [BHTSettings integerForKey:@"undo_tweet_timeout"] > 0;
}

BOOL FastBlockEnabled(void) {
    return [BHTSettings boolForKey:@"fast_block"];
}

void PlayCustomSendSound(void) {
    NSString* path = [[NSUserDefaults standardUserDefaults] stringForKey:@"custom_send_sound_path"];
    if (path.length == 0) {
        return;
    }

    static AVAudioPlayer* player;
    NSError* error = nil;
    player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                    error:&error];
    if (player && [player prepareToPlay]) {
        [player play];
    }
}

// Set while a block confirmation alert is expected, so the alert can be
// answered without being shown (Fast block/mute, below).

void ShowConfirmation(void (^confirmed)(void)) {
    [(Class)objc_getClass("FLEXAlert")
        makeAlert:^(FLEXAlert* make) {
            make.message([[BHTBundle sharedBundle]
                localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);

            make.button([[BHTBundle sharedBundle]
                            localizedStringForKey:@"YES_ACTION_LABEL"])
                .handler(^(NSArray<NSString*>* strings) {
                    confirmed();
                });

            make.button([[BHTBundle sharedBundle]
                            localizedStringForKey:@"NO_ACTION_LABEL"])
                .cancelStyle();
        }
         showFrom:topMostController()];
}
