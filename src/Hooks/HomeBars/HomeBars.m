#import "HomeBars.h"

// Applies a toggle without relaunching. Hiding rewrites the UNCHANGED pinned
// list purely to republish — updatePinnedTimelines: persists server-side, so
// anything else would unpin for real; the delegate hook below swaps in the
// empty list on the way through.
void applyHideCustomTimelinesSetting(void) {
    NSObject* repository = PinnedTimelinesRepository;
    if (!repository) {
        return;
    }

    if ([BHTSettings boolForKey:@"hide_custom_timelines"]) {
        NSArray* models = LastPinnedTimelineModels;
        if (models.count > 0) {
            PinnedTimelinesWriteBypass = YES;
            ((void (*)(id, SEL, id))objc_msgSend)(repository, @selector(updatePinnedTimelines:), models);
            PinnedTimelinesWriteBypass = NO;
        }
    } else if ([repository respondsToSelector:@selector(fetchPinnedTimelinesWithThrottleEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            repository, @selector(fetchPinnedTimelinesWithThrottleEnabled:), NO);
    }
}

// The trailing accessory is only reconfigured while the strip is showing, so a
// button built before hiding mid-session survives; sync its visibility here. The
// property is a Swift lazy var whose storage ivar KVC can't see, hence the fallback.
void SyncHomeAddTabButton(id container, BOOL hidden) {
    UIView* button = nil;

    @try {
        button = [container valueForKey:@"addTabButton"];
    } @catch (__unused NSException* exception) {
        unsigned int ivarCount = 0;
        Ivar* ivars = class_copyIvarList([container class], &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char* name = ivar_getName(ivars[i]);
            if (name && strstr(name, "addTabButton")) {
                button = object_getIvar(container, ivars[i]);
                break;
            }
        }
        free(ivars);
    }

    if ([button isKindOfClass:[UIView class]]) {
        button.hidden = hidden;
    }
}
