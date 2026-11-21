#import "../HookHelpers.h"

BOOL StatusItemIsPromoted(id item);
BOOL IsImmersiveTimelineURL(NSURL* url);
BOOL ImmersiveCardIsPromoted(id card);
id RemovePromotedEntries(id node, BOOL* removed);
void RemovePromotedImmersiveCards(id viewController);
NSArray* FilteredSections(TFNItemsDataViewController* dataViewController,
                          NSArray* sections);
