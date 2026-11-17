#import "ReplySorting.h"

// MARK: - Default reply sort

%hook TFNActionItem

+ (id)actionItemWithTitle:(id)title imageName:(id)imageName action:(void (^)(void))action {
    if (!action) {
        return %orig;
    }

    void (^wrapped)(void) = ^{
        PerformReplySortingUserAction(action);
    };
    return %orig(title, imageName, wrapped);
}

%end

%hook TFSReplySortingState

- (id)init {
    self = %orig;
    uint8_t mode;
    if (self && PreferredReplyRankingMode(&mode)) {
        switch (mode) {
            case BHTReplyRankingModeRecency:
                [self sortByRecency];
                break;
            case BHTReplyRankingModeLikes:
                [self sortByLikes];
                break;
            default:
                [self sortByRelevance];
                break;
        }
    }
    return self;
}

%end

%ctor {
    %init;

    InstallReplySortingStateHook();
}
