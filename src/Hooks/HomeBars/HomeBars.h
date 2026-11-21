#import <string.h>
#import "../HookHelpers.h"

extern __weak NSObject* PinnedTimelinesRepository;
extern NSArray* LastPinnedTimelineModels;
extern BOOL PinnedTimelinesWriteBypass;

void applyHideCustomTimelinesSetting(void);
void SyncHomeAddTabButton(id container, BOOL hidden);
