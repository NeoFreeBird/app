#import <string.h>
#import "../HookHelpers.h"

static __weak NSObject* PinnedTimelinesRepository;
static NSArray* LastPinnedTimelineModels;
static BOOL PinnedTimelinesWriteBypass = NO;

void applyHideCustomTimelinesSetting(void);
void SyncHomeAddTabButton(id container, BOOL hidden);
