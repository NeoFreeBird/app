#import "FeatureSwitches.h"
#import "FeatureSwitchRules.h"

@interface BHTFeatureSwitchRule ()
@property (nonatomic, copy, readwrite) NSSet<NSString*>* keys;
@property (nonatomic, copy, readwrite) NSString* prefix;
@property (nonatomic, copy, readwrite) NSString* suffix;
@property (nonatomic, copy, readwrite) NSString* setting;
@property (nonatomic, strong, readwrite) NSNumber* enabledValue;
@property (nonatomic, strong, readwrite) NSNumber* disabledValue;
@property (nonatomic, readwrite) BHTFeatureSwitchPolicy policy;
@end

__thread BOOL DashPanelIDQuery = NO;
__thread BOOL ReportGenuineSubscription = NO;
__thread BOOL ReportGenuineTabGates = NO;
static char SensitiveMediaRevealPendingKey;
static char SensitiveMediaButtonHiddenKey;

@implementation BHTFeatureSwitchRule
@end

static BOOL AccountIsGenuinelyPremium(void) {
    Class hostClass = objc_getClass("T1HostViewController");
    id host = ((id (*)(id, SEL))objc_msgSend)(
        (id)hostClass, @selector(sharedHostViewController));
    id account = ((id (*)(id, SEL))objc_msgSend)(host, @selector(currentAccount));
    if (![account respondsToSelector:@selector(isPremiumTierUser)]) {
        return NO;
    }

    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    BOOL premium =
        ((BOOL (*)(id, SEL))objc_msgSend)(account, @selector(isPremiumTierUser));
    ReportGenuineSubscription = saved;
    return premium;
}

static id accountFeatureSwitches(void) {
    Class switchesClass = objc_getClass("TFSAccountFeatureSwitches");
    if (![(id)switchesClass
            respondsToSelector:@selector(lastUsedAccountFeatureSwitches)]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(
        (id)switchesClass, @selector(lastUsedAccountFeatureSwitches));
}

static BOOL genuineTabGateFlag(id receiver, SEL selector) {
    if (![receiver respondsToSelector:selector]) {
        return NO;
    }

    BOOL saved = ReportGenuineTabGates;
    ReportGenuineTabGates = YES;
    BOOL value = ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
    ReportGenuineTabGates = saved;
    return value;
}

static id featureSwitchesProvider(void) {
    id accountSwitches = accountFeatureSwitches();
    if (![accountSwitches respondsToSelector:@selector(provider)]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(accountSwitches, @selector(provider));
}

static BOOL genuineSwitchBool(NSString* key) {
    id provider = featureSwitchesProvider();
    if (![provider respondsToSelector:@selector(boolForKey:)]) {
        return NO;
    }

    BOOL saved = ReportGenuineTabGates;
    ReportGenuineTabGates = YES;
    BOOL value = ((BOOL (*)(id, SEL, NSString*))objc_msgSend)(
        provider, @selector(boolForKey:), key);
    ReportGenuineTabGates = saved;
    return value;
}

static BOOL RuleMatchesKey(BHTFeatureSwitchRule* rule, NSString* key) {
    if ([rule.keys containsObject:key]) {
        return YES;
    }
    return rule.prefix && [key hasPrefix:rule.prefix] &&
           (!rule.suffix || [key hasSuffix:rule.suffix]);
}

// X's own Show/Hide button, or nil until the overlay has created and attached it.
static UIButton* BHTSensitiveMediaRevealButton(HFSensitiveTweetBlurredInterstitialView* overlay) {
    UIButton* button = objectIvar(overlay, "$__lazy_storage_$_showOrHideMediaButton");
    if (![button isKindOfClass:UIButton.class] || ![button isDescendantOfView:overlay]) {
        return nil;
    }
    return button;
}

void BHTUpdateSensitiveMediaRevealButton(HFSensitiveTweetBlurredInterstitialView* overlay) {
    UIButton* button = BHTSensitiveMediaRevealButton(overlay);
    if (!button) {
        return;
    }

    BOOL shouldHide = [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"] &&
                      [overlay respondsToSelector:@selector(blurViewIsHidden)] &&
                      overlay.blurViewIsHidden;
    if (shouldHide && !button.hidden) {
        objc_setAssociatedObject(button, &SensitiveMediaButtonHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        button.hidden = YES;
    } else if (!shouldHide && objc_getAssociatedObject(button, &SensitiveMediaButtonHiddenKey)) {
        objc_setAssociatedObject(button, &SensitiveMediaButtonHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        button.hidden = NO;
    }
}

static void BHTRevealSensitiveMedia(HFSensitiveTweetBlurredInterstitialView* overlay) {
    if (!overlay.window || overlay.hidden ||
        ![BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"] ||
        ![overlay respondsToSelector:@selector(blurViewIsHidden)] || overlay.blurViewIsHidden ||
        ![overlay respondsToSelector:@selector(delegate)] ||
        ![overlay respondsToSelector:@selector(showOrHideMediaButtonPressed:)]) {
        return;
    }

    id<BHTSensitiveMediaOverlayDelegate> delegate = overlay.delegate;
    if (![delegate respondsToSelector:@selector(blurViewRequiresAgeVerificationToRevealWithBlurView:)] ||
        [delegate blurViewRequiresAgeVerificationToRevealWithBlurView:overlay]) {
        return;
    }

    // Use the native Show action
    UIButton* button = BHTSensitiveMediaRevealButton(overlay);
    if (!button) {
        return;
    }
    [overlay showOrHideMediaButtonPressed:button];
    BHTUpdateSensitiveMediaRevealButton(overlay);
}

void BHTScheduleSensitiveMediaReveal(HFSensitiveTweetBlurredInterstitialView* overlay) {
    if (!overlay.window || ![BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"] ||
        objc_getAssociatedObject(overlay, &SensitiveMediaRevealPendingKey)) {
        return;
    }

    objc_setAssociatedObject(overlay, &SensitiveMediaRevealPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Let X finish configuring the view and its delegate before revealing the media.
    __weak HFSensitiveTweetBlurredInterstitialView* weakOverlay = overlay;
    dispatch_async(dispatch_get_main_queue(), ^{
        HFSensitiveTweetBlurredInterstitialView* attachedOverlay = weakOverlay;
        if (attachedOverlay) {
            BHTRevealSensitiveMedia(attachedOverlay);
            objc_setAssociatedObject(attachedOverlay, &SensitiveMediaRevealPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

#pragma mark - Rule descriptions

BHTFeatureSwitchRule* BHTSettingSwitches(NSArray<NSString*>* keys, NSString* setting,
                                         NSNumber* enabledValue, NSNumber* disabledValue) {
    BHTFeatureSwitchRule* rule = [BHTFeatureSwitchRule new];
    rule.keys = [NSSet setWithArray:keys];
    rule.setting = setting;
    rule.enabledValue = enabledValue;
    rule.disabledValue = disabledValue;
    return rule;
}

BHTFeatureSwitchRule* BHTFixedSwitches(NSArray<NSString*>* keys, NSNumber* value) {
    return BHTSettingSwitches(keys, nil, value, nil);
}

BHTFeatureSwitchRule* BHTPatternSwitches(NSString* prefix, NSString* suffix, NSString* setting,
                                         NSNumber* enabledValue, NSNumber* disabledValue) {
    BHTFeatureSwitchRule* rule = BHTSettingSwitches(@[], setting, enabledValue, disabledValue);
    rule.prefix = prefix;
    rule.suffix = suffix;
    return rule;
}

BHTFeatureSwitchRule* BHTTabGateSwitches(NSArray<NSString*>* keys) {
    BHTFeatureSwitchRule* rule = BHTFixedSwitches(keys, @YES);
    rule.policy = BHTFeatureSwitchPolicyTabGate;
    return rule;
}

BHTFeatureSwitchRule* BHTBrandedSwitches(NSArray<NSString*>* keys, NSNumber* twitterValue,
                                         NSNumber* otherValue) {
    BHTFeatureSwitchRule* rule = BHTSettingSwitches(keys, nil, twitterValue, otherValue);
    rule.policy = BHTFeatureSwitchPolicyBranding;
    return rule;
}

BHTFeatureSwitchRule* BHTPremiumSwitches(NSArray<NSString*>* keys) {
    BHTFeatureSwitchRule* rule = BHTFixedSwitches(keys, @NO);
    rule.policy = BHTFeatureSwitchPolicyPremium;
    return rule;
}

#pragma mark - Evaluation

NSNumber* BHTFeatureSwitchOverrideValue(NSString* key, BOOL reportGenuineTabGates,
                                        BOOL (^isGenuinelyPremium)(void)) {
    if (![key isKindOfClass:NSString.class]) {
        return nil;
    }

    for (BHTFeatureSwitchRule* rule in BHTFeatureSwitchRules()) {
        if (!RuleMatchesKey(rule, key)) {
            continue;
        }
        switch (rule.policy) {
            case BHTFeatureSwitchPolicyTabGate:
                return reportGenuineTabGates ? nil : rule.enabledValue;
            case BHTFeatureSwitchPolicyBranding:
                return [BHTManager isTwitterBranded] ? rule.enabledValue : rule.disabledValue;
            case BHTFeatureSwitchPolicyPremium:
                return isGenuinelyPremium() ? nil : rule.enabledValue;
            case BHTFeatureSwitchPolicySetting:
                return !rule.setting || [BHTSettings boolForKey:rule.setting]
                           ? rule.enabledValue
                           : rule.disabledValue;
        }
    }
    return nil;
}

NSNumber* FeatureSwitchOverrideValueForKey(NSString* key) {
    return BHTFeatureSwitchOverrideValue(key, ReportGenuineTabGates,
                                         ^BOOL { return AccountIsGenuinelyPremium(); });
}

BOOL panelIsGenuinelyAvailable(long long panelID) {
    switch (panelID) {
        case 13: { // Community Notes
            id switches = accountFeatureSwitches();
            return genuineTabGateFlag(switches,
                                      @selector(birdwatchHomePageIsEnabled)) &&
                   genuineTabGateFlag(switches, @selector(birdwatchHistoryIsEnabled));
        }
        case 15: // Premium hub
            return genuineSwitchBool(@"subscriptions_premium_hub_enabled");
        case 16: // Jobs
            return genuineSwitchBool(@"recruiting_global_jobs_hub_enabled") ||
                   genuineSwitchBool(@"recruiting_jetfuel_jobs_hub_enabled");
        case 17: { // Money
            id host =
                ((id (*)(id, SEL))objc_msgSend)(objc_getClass("T1HostViewController"),
                                                @selector(sharedHostViewController));
            id account =
                ((id (*)(id, SEL))objc_msgSend)(host, @selector(currentAccount));
            return genuineTabGateFlag(account, @selector(canAccessXPayments));
        }
        default:
            return YES;
    }
}

// [T1PanelIdentity iconImageNameForPanelID:] is where you can match panel IDs to their icons (the enum essentially)
// Claiming panels stops them from displaying
NSArray* panelIDsForDashSnapshot(NSArray* panelIDs) {
    if (!DashPanelIDQuery || !panelIDs) {
        return panelIDs;
    }

    NSMutableArray* spoofed = [panelIDs mutableCopy];
    void (^claim)(NSNumber*) = ^(NSNumber* panelID) {
        if (![spoofed containsObject:panelID]) {
            [spoofed addObject:panelID];
        }
    };

    for (NSNumber* panelID in @[@13, @15, @16, @17]) {
        if (!panelIsGenuinelyAvailable(panelID.longLongValue)) {
            claim(panelID);
        }
    }

    if ([BHTSettings boolForKey:@"hide_grok_sidebar"]) {
        claim(@14);
    }

    if (!AccountIsGenuinelyPremium()) {
        claim(@15);
    }
    claim(@17); // Money
    claim(@20); // News
    claim(@25); // Calls

    return spoofed;
}
