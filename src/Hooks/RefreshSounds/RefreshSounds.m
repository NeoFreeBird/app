#import "RefreshSounds.h"

// 12.3's TFNPullToRefreshControl has no built-in sound path (no soundEffects gate,
// no bundled psst/pop assets), so we play the tweak-bundled sounds ourselves at the
// control's state transitions.

void PlayRefreshSound(RefreshSound type) {
    if (![BHTSettings boolForKey:@"restore_refresh_sounds"]) {
        return;
    }

    // SystemSoundIDs are a global audio resource, so cache one per sound type
    // instead of re-decoding.
    static SystemSoundID sounds[2] = {0, 0};
    static BOOL initialized[2] = {NO, NO};

    if (!initialized[type]) {
        NSString* soundFile = (type == RefreshSoundPull) ? @"psst2.aac" : @"pop.aac";
        NSURL* soundURL = [[BHTBundle sharedBundle] pathForFile:soundFile];

        if (soundURL && AudioServicesCreateSystemSoundID((__bridge CFURLRef)soundURL, &sounds[type]) ==
                            kAudioServicesNoError) {
            initialized[type] = YES;
        }
    }

    if (initialized[type]) {
        AudioServicesPlaySystemSound(sounds[type]);
    }
}
