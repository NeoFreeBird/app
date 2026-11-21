#import "../HookHelpers.h"

extern __thread BOOL DashPanelIDQuery;
extern __thread BOOL ReportGenuineSubscription;
extern __thread BOOL ReportGenuineTabGates;

// nil lets X handle the value, YES/NO overrides it
NSNumber* BHTFeatureSwitchOverrideValue(NSString* key, BOOL reportGenuineTabGates,
                                        BOOL (^isGenuinelyPremium)(void));
NSNumber* FeatureSwitchOverrideValueForKey(NSString* key);
BOOL panelIsGenuinelyAvailable(long long panelID);
NSArray* panelIDsForDashSnapshot(NSArray* panelIDs);
void BHTUpdateSensitiveMediaRevealButton(HFSensitiveTweetBlurredInterstitialView* overlay);
void BHTScheduleSensitiveMediaReveal(HFSensitiveTweetBlurredInterstitialView* overlay);
