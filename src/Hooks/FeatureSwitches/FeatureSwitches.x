#import "FeatureSwitches.h"

static __thread NSUInteger NFBLiquidGlassInstallationDepth;

// MARK: - Feature switch overrides

%hook TFSFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)integerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (NSNumber*)numberForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (id)rawValueForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (double)doubleForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.doubleValue : %orig;
}

- (double)unsafePeekDoubleForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.doubleValue : %orig;
}

// Some reads, like the default captions setup, only consult the value when the
// switch reports a non-default one.
- (BOOL)hasNonDefaultValueForKey:(NSString*)key {
    return FeatureSwitchOverrideValueForKey(key) ? YES : %orig;
}

%end

%hook TFSInstrumentedFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)integerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (NSNumber*)numberForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (id)rawValueForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (BOOL)hasNonDefaultValueForKey:(NSString*)key {
    return FeatureSwitchOverrideValueForKey(key) ? YES : %orig;
}

- (double)doubleForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.doubleValue : %orig;
}

- (double)unsafePeekDoubleForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.doubleValue : %orig;
}

%end

// MARK: - Typed feature switch accessors

%hook TFSAccountFeatureSwitches

- (BOOL)isAutoplayBackgroundAudioSuppressionEnabled {
    return NO;
}

+ (BOOL)isShowsVerticalScrollIndicatorEnabled {
    return [BHTSettings boolForKey:@"show_scroll_indicator"] ? YES : %orig;
}

- (BOOL)isSubscriptionsSettingsItemEnabledWithProvider:(id)provider {
    if (![provider respondsToSelector:@selector(isPremiumTierUser)]) {
        return %orig;
    }

    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    BOOL genuinePremium =
        ((BOOL (*)(id, SEL))objc_msgSend)(provider, @selector(isPremiumTierUser));
    ReportGenuineSubscription = saved;

    if (!genuinePremium) {
        return NO;
    }
    return %orig;
}

- (BOOL)birdwatchHomePageIsEnabled {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

- (BOOL)birdwatchHistoryIsEnabled {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

- (BOOL)isVideoCacheEnabled {
    return YES;
}

%end

// MARK: - Override the login screens

%hook T1AccountsViewController

- (void)private_startLoginFlowWithSender:(id)sender {
    [WebLoginViewController presentLoginFrom:(UIViewController*)self];
}

%end

%hook T1HostViewController

- (void)makeOnboardingViewControllerWithCompletion:(void (^)(id))completion {
    if (completion == nil) {
        %orig;
        return;
    }
    completion([WebLoginViewController loginRootNavigationController]);
}

%end

// MARK: - High quality images

%hook T1ImageDisplayView

- (BOOL)_tfn_shouldUseHighestQualityImage {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

- (BOOL)_tfn_shouldUseHighQualityImage {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

%end

// MARK: - Promoted content

%hook TFNTwitterAPICommandContext

- (BOOL)allowPromotedContent {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

%end

// MARK: - Account feature gates

%hook TFNTwitterAccount

// Every account-level premium check funnels through -isSubscribedTo:
// (isPremiumTierUser checks tiers 0/7/8, isVerifiedPremiumTierUser 0/8), so
// forcing those tiers here unlocks premium from one stable seam.
- (BOOL)isSubscribedTo:(NSUInteger)tier {
    if (!ReportGenuineSubscription && (tier == 0 || tier == 7 || tier == 8)) {
        return YES;
    }
    return %orig;
}

- (BOOL)isEditProfileUsernameEnabled {
    return YES;
}

- (BOOL)isSensitiveTweetWarningsComposeEnabled {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
}

- (BOOL)isSensitiveTweetWarningsConsumeEnabled {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
}

- (BOOL)isAgeAssuranceAgeVerificationFlowEnabled {
    return [BHTSettings boolForKey:@"bypass_age_verification"] ? NO : %orig;
}

- (BOOL)isVideoDynamicAdEnabled {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isDoubleMaxZoomFor4KImagesEnabled {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

// This keeps the panel removal working
- (BOOL)canAccessXPayments {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

%end

// MARK: - Genuine subscription status

%hook T1AppServicesManager

// Sets the account's tier as a Braze attribute on every activation.
- (id)_brazeTierStringForAccount:(id)account {
    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    id result = %orig;
    ReportGenuineSubscription = saved;
    return result;
}

%end

%hook T1TabbedAppNavigation

- (void)showPremiumHubManageSubscriptionWithSource:(NSInteger)source
                                    withCompletion:(id)completion {
    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    %orig;
    ReportGenuineSubscription = saved;
}

%end

%hook T1ProfileSummaryView

- (BOOL)shouldShowUnderReviewButton {
    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    BOOL result = %orig;
    ReportGenuineSubscription = saved;
    return result;
}

%end

// MARK: - Custom navigation - genuine panel availability

%hook T1DashContentController

- (void)updateVisiblePanelIDs {
    BOOL saved = DashPanelIDQuery;
    DashPanelIDQuery = YES;
    @try {
        %orig;
    } @finally {
        DashPanelIDQuery = saved;
    }
}

%end

%hook T1TabbedAppNavigationViewController

- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation {
    NSArray* panelIDs = %orig;
    return panelIDsForDashSnapshot(panelIDs);
}

%end

// Swift version of above class
%hook _TtC14T1TwitterSwift20XTabbedAppNavigation

- (NSArray*)visiblePanelIDs {
    NSArray* panelIDs = %orig;
    return panelIDsForDashSnapshot(panelIDs);
}

%end

// MARK: - Grok creation - photo editor

%hook T1TweetComposeViewController

- (BOOL)photoEditorCanEditWithGrok:(id)photoEditor {
    return [BHTSettings boolForKey:@"hide_grok_create"] ? NO : %orig;
}

%end

%hook T1StatusPhotoEditorHandler

- (BOOL)photoEditorCanEditWithGrok:(id)photoEditor {
    return [BHTSettings boolForKey:@"hide_grok_create"] ? NO : %orig;
}

%end

// MARK: - Sensitive media warnings

%hook TFNTwitterStatus

- (BOOL)hasImageInterstitial {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
}

- (id)imageInterstitial {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? nil
               : %orig;
}

- (id)innerImageInterstitial {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? nil
               : %orig;
}

- (BOOL)isPossiblySensitiveViewModelForAccount:(id)account {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
}

%end

%hook HFHealthSafetyFeature

+ (BOOL)isTweetMedialInterstitialEnabled:(id)featureSwitches {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
}

%end

%hook HFSensitiveTweetBlurredInterstitialView

- (void)didMoveToWindow {
    %orig;
    BHTUpdateSensitiveMediaRevealButton(self);
    BHTScheduleSensitiveMediaReveal(self);
}

- (void)layoutSubviews {
    %orig;
    BHTUpdateSensitiveMediaRevealButton(self);
}

- (void)setBlurViewIsHidden:(BOOL)hidden {
    %orig;
    BHTUpdateSensitiveMediaRevealButton(self);
    if (!hidden) {
        BHTScheduleSensitiveMediaReveal(self);
    }
}

%end

// MARK: - Video upload quality
%hook T1VideoQualityUploadSettings
- (BOOL)shouldAllowFullHdVideoUpload:(long long)upload {
    return [BHTSettings boolForKey:@"upload_full_hd_videos"] ? YES : %orig;
}
%end

%hook T1LongerVideoUploadEnabledConfig

- (BOOL)isUploadFullHDVideoEnabled {
    return [BHTSettings boolForKey:@"upload_full_hd_videos"] ? YES : %orig;
}

- (BOOL)isUploadFullHDVideoEnabledByDefault {
    return [BHTSettings boolForKey:@"upload_full_hd_videos"] ? YES : %orig;
}

%end

%hook T1LiquidGlassGateInstaller

+ (void)installGateForAccount:(id)account {
    NFBLiquidGlassInstallationDepth++;
    @try {
        %orig(account);
    } @finally {
        NFBLiquidGlassInstallationDepth--;
    }

    // In 12.38 this selector got removed, so this is to prevent a crash
    SEL install = @selector(installGateWithRedesignEnabled:);
    if ([self respondsToSelector:install]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, install, NFBLiquidGlassEnabled());
    }
}

%end

%hook TFNTwitterAccount

- (BOOL)isDummyTest1FeatureEnabled {
    return NFBLiquidGlassInstallationDepth ? NFBLiquidGlassEnabled() : %orig;
}

%end

%hook _TtC14T1TwitterSwift27LiquidGlassRedesignFeatures

- (instancetype)initWithFeatureSwitches:(id)switches
                isSecondFactorSatisfied:(BOOL)satisfied {
    return %orig(switches, NFBLiquidGlassEnabled());
}

- (BOOL)isRedesignEnabled {
    return NFBLiquidGlassEnabled();
}

%end
