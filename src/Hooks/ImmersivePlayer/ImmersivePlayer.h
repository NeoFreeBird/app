#import "../HookHelpers.h"

static const void* kBHTRestoredTimestampKey = &kBHTRestoredTimestampKey;
static const void* kBHTTwoFingerTapKey = &kBHTTwoFingerTapKey;

// Field indexes in ImmersiveCardState's declaration order.
enum {
    CardStateFieldIsPanningBetweenCards = 19,
    CardStateFieldIsChromeFadedOutWhilePanning = 20,
};

// VideoControlsView.ProgressLabelMode, a payload-free Swift enum stored in a
// single byte.
enum {
    ProgressLabelModeRemaining = 0,
    ProgressLabelModeTotal = 1,
};

BOOL isImmersiveCardPan(id viewController,
                        UIGestureRecognizer* gesture);
BOOL isUpwardPan(UIGestureRecognizer* gesture);
TAVPlayer* immersivePagePlayer(UIView* pageView);
void togglePlayback(TAVPlayer* player);
