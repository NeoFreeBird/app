#import "RefreshSounds.h"

// MARK: - Restore Pull-To-Refresh Sounds

%hook TFNPullToRefreshControl

static char kManualRefreshKey;

- (void)_setStatus:(unsigned long long)status fromScrolling:(BOOL)fromScrolling {
    BOOL wasActive = [self loading];

    %orig;

    if (status == 1 && !wasActive && fromScrolling) {
        PlayRefreshSound(RefreshSoundPull);
        objc_setAssociatedObject(self, &kManualRefreshKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (status == 0 && wasActive) {
        if ([objc_getAssociatedObject(self, &kManualRefreshKey) boolValue]) {
            PlayRefreshSound(RefreshSoundPop);
        }
        objc_setAssociatedObject(self, &kManualRefreshKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

%ctor {
    // AudioToolbox isn't in the tweak's linked frameworks; bind its symbols lazily.
    dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_LAZY);

    %init;
}
