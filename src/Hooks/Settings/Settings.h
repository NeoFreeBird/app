#import "../HookHelpers.h"

static const void* SettingsEntryKey = &SettingsEntryKey;
static const void* SettingsRootKey = &SettingsRootKey;
static const void* SettingsGestureKey = &SettingsGestureKey;

void insertNeoFreeBirdSettingsIfRoot(TFNItemsDataViewController* settingsVC);
NSArray* sectionsWithNeoFreeBirdEntry(TFNItemsDataViewController* settingsVC,
                                      NSArray* sections);
