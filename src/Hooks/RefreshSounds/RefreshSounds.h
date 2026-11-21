#import "../HookHelpers.h"

typedef NS_ENUM(NSInteger, RefreshSound) {
    RefreshSoundPull = 0, // Dragging down past the threshold to refresh
    RefreshSoundPop = 1   // Manual refresh completed
};

void PlayRefreshSound(RefreshSound type);
