#import "../HookHelpers.h"

static const void* SettingsGestureKey = &SettingsGestureKey;
static const void* SettingsRootKey = &SettingsRootKey;
static const void* SettingsEntryKey = &SettingsEntryKey;

void insertNeoFreeBirdSettingsIfRoot(TFNItemsDataViewController* settingsVC);
NSArray* sectionsWithNeoFreeBirdEntry(TFNItemsDataViewController* settingsVC,
                                      NSArray* sections);
