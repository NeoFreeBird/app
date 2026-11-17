#import "../HookHelpers.h"

// Raw ranking-mode values used by TFSReplySortingState
enum {
    BHTReplyRankingModeLikes = 0,
    BHTReplyRankingModeRecency = 1,
    BHTReplyRankingModeRelevance = 2,
};

BOOL PreferredReplyRankingMode(uint8_t* mode);
void PerformReplySortingUserAction(void (^action)(void));
void InstallReplySortingStateHook(void);
