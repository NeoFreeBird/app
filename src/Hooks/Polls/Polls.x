#import "Polls.h"

%hook TFCCardData

- (NSString*)stringForKey:(NSString*)key {
    NSString* title = %orig;
    return BHTPollTitleWithPercentage(self, key, title);
}

- (NSString*)stringForKey:(NSString*)key defaultValue:(NSString*)value {
    NSString* title = %orig;
    return BHTPollTitleWithPercentage(self, key, title);
}

%end
