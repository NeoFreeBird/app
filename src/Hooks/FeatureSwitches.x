//
//  FeatureSwitches.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// While set, -isSubscribedTo: (below) reports the account's genuine
// subscription state instead of the forced premium tiers, so paths that need
// the real status can read through the unlock.
static __thread BOOL ReportGenuineSubscription = NO;

// While set, the custom-navigation tab gates (below) report their real values,
// so callers can tell genuinely-held panels from ones only unlocked for the tab
// pool.
static __thread BOOL ReportGenuineTabGates = NO;

// Whether the account is really a premium subscriber, ignoring the forced
// unlock — for switch-gated surfaces that have no premium-aware seam of their
// own.
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

// MARK: - Feature switch overrides

static NSNumber* FeatureSwitchOverrideValueForKey(NSString* key) {
    if (![key isKindOfClass:[NSString class]]) {
        return nil;
    }

    // Custom timelines overrides
    BOOL hideCustomTimelines = [BHTSettings boolForKey:@"hide_custom_timelines"];
    if ([key isEqualToString:@"hometimeline_pinned_tabs_topics_enabled"] ||
        [key isEqualToString:
                 @"hometimeline_pinned_tabs_generic_timelines_enabled"] ||
        [key isEqualToString:
                 @"hometimeline_pinned_tabs_sticky_warm_start_enabled"] ||
        [key
            isEqualToString:
                @"super_follow_subscriptions_home_timeline_tab_sticky_enabled"]) {
        return hideCustomTimelines ? @NO : @YES;
    }

    // Keeps the selected timeline tab across sessions.
    if ([key isEqualToString:
                 @"home_timeline_non_sticky_tab_on_new_session_enabled"]) {
        return @NO;
    }

    if ([key isEqualToString:@"hometimeline_pinned_tabs_limit"] ||
        [key isEqualToString:@"hometimeline_pinned_tabs_management_pinnedsection_"
                             @"inline_limit"] ||
        [key isEqualToString:
                 @"hometimeline_pinned_tabs_management_topics_inline_limit"]) {
        return hideCustomTimelines ? @0 : @100;
    }

    // Gates the add-tab (+) accessory button on the home tab bar.
    if ([key isEqualToString:
                 @"hometimeline_pinned_tabs_pinned_trailing_accessory_enabled"]) {
        return hideCustomTimelines ? @NO : nil;
    }


    // Restore the animated launch screen (AppLifecycle.x strips its X-shaped
    // reveal mask)
    if ([key isEqualToString:@"app_launch_animated_launch_screen_enabled"]) {
        return @YES;
    }

    // Grok translations
    if ([key isEqualToString:
                 @"grok_translations_bio_inline_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_bio_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_post_inline_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_post_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_community_note_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_poll_translation_is_enabled"]) {
        return @YES;
    }

    // Checked before the per-language preference, so turning these off stops all
    // auto translation while manual translate stays.
    if ([key isEqualToString:
                 @"grok_translations_post_auto_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_bio_auto_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_community_note_auto_translation_"
                             @"is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_notification_auto_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_immersive_auto_translate_is_enabled"]) {
        return [BHTSettings boolForKey:@"disable_auto_translate"] ? @NO : nil;
    }

    // Grok buttons
    if ([key isEqualToString:@"grok_ask_grok_button_under_post_focal_enabled"] ||
        [key
            isEqualToString:@"grok_ask_grok_button_under_post_preview_enabled"]) {
        return @YES;
    }

    if ([key isEqualToString:
                 @"grok_edit_with_grok_button_under_post_focal_enabled"] ||
        [key isEqualToString:
                 @"grok_edit_with_grok_button_under_post_preview_enabled"]) {
        return @(![BHTSettings boolForKey:@"hide_grok_create"]);
    }

    // Grok creation surfaces: composer buttons, imagine menus and CTAs, Edit with
    // Grok on photo posts, and the immersive player's create-your-own button.
    if ([key isEqualToString:@"ios_composer_grok_button_enabled"] ||
        [key isEqualToString:@"grok_imagine_composer_enabled"] ||
        [key isEqualToString:@"grok_composer_imagine_is_enabled"] ||
        [key isEqualToString:
                 @"grok_composer_attachment_imagine_menu_is_enabled"] ||
        [key isEqualToString:@"grok_timeline_preview_imagine_menu_is_enabled"] ||
        [key isEqualToString:@"grok_timeline_video_imagine_menu_is_enabled"] ||
        [key
            isEqualToString:@"grok_timeline_slideshow_imagine_menu_is_enabled"] ||
        [key isEqualToString:@"grok_ios_edit_photo_post_button_enabled"] ||
        [key isEqualToString:@"grok_ios_imagine_cta_focal_enabled"] ||
        [key isEqualToString:@"grok_ios_imagine_cta_reply_enabled"] ||
        [key isEqualToString:@"grok_ios_imagine_cta_timeline_enabled"] ||
        [key isEqualToString:@"grok_ios_imagine_cta_profile_enabled"] ||
        [key isEqualToString:@"grok_immersive_create_own_button_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_create"] ? @NO : nil;
    }

    // Disguised switch family for the Grok edit-photo and create-own buttons,
    // read only by Grok.GrokFeatureAccess.
    if ([key hasPrefix:@"ios_button_layout_fix"] && [key hasSuffix:@"_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_create"] ? @NO : nil;
    }

    // Grok analyze: every tweet-side show decision gates on this backend switch
    // before consulting the per-tweet flag.
    if ([key isEqualToString:
                 @"grok_ios_author_view_analyze_button_via_backend_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_analyze"] ? @NO : nil;
    }

    // The profile header's analyze (summary) button bottoms out in this switch on
    // both header variants, one of which reads it through a direct Swift call.
    if ([key isEqualToString:@"grok_ios_profile_summary_enabled"]) {
        return @(![BHTSettings boolForKey:@"hide_grok_analyze"]);
    }

    if ([key isEqualToString:@"grok_ios_grok_bot_upsells_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_sidebar_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_home_header_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_home_hero_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_preset_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_tab_icon_enabled"]) {
        return @NO;
    }

    // Session token appended to shared/copied links (&t=)
    if ([key isEqualToString:@"rehire_share_update_url_enabled"]) {
        return @NO;
    }

    // Click IDs on promoted links, and loading card links in the background
    // before they're tapped (LinkTracking.x).
    if ([key isEqualToString:@"ad_formats_click_id_enabled"] ||
        [key isEqualToString:@"wcl_unified_cards_likely_open_link_prefetch_enabled"]) {
        if ([BHTSettings boolForKey:@"block_link_tracking"]) {
            return @NO;
        }
    }

    // The profile hooks build on the classic header; the header rework
    // replaces the action-buttons row with a separate catalog system.
    if ([key isEqualToString:@"ios_profile_redesign_header_rework_enabled"]) {
        return @NO;
    }

    // The NeoFreeBird entry is inserted into the classic settings list. The
    // XSettings redesign bypasses those controllers entirely.
    if ([key isEqualToString:@"ios_settings_redesign_enabled"]) {
        return @NO;
    }

    // Profile tabs
    if ([key isEqualToString:@"articles_timeline_profile_tab_enabled"]) {
        return @(![BHTSettings boolForKey:@"disable_articles"]);
    }

    if ([key isEqualToString:@"highlights_tweets_tab_ui_enabled"]) {
        return @(![BHTSettings boolForKey:@"disable_highlights"]);
    }

    // Age verification bypass
    if ([key hasPrefix:@"ios_age_assurance"] ||
        [key isEqualToString:@"grok_settings_age_restriction_enabled"]) {
        if ([BHTSettings boolForKey:@"bypass_age_verification"]) {
            return @NO;
        }
    }

    // Conversation / tweet detail
    if ([key isEqualToString:@"reply_sorting_enabled"]) {
        return @(![BHTSettings boolForKey:@"reply_sorting"]);
    }

    if ([key
            isEqualToString:@"ios_tweet_detail_overflow_in_navigation_enabled"]) {
        return @NO;
    }

    if ([key isEqualToString:
                 @"ios_tweet_detail_conversation_context_removal_enabled"]) {
        return @(![BHTSettings boolForKey:@"restore_reply_context"]);
    }

    if ([key isEqualToString:@"ios_ui_multi_media_carousel_avatar_avoidance_enabled"] ||
        [key isEqualToString:@"ios_ui_multi_media_carousel_enabled"] ||
        [key isEqualToString:@"ios_ui_quote_tweet_multi_media_carousel_enabled"]) {
        if ([BHTSettings boolForKey:@"disable_media_carousel"]) {
            return @NO;
        }
    }

    // Video captions
    if ([key isEqualToString:@"ios_tav_default_closed_captions_enabled"] ||
        [key isEqualToString:@"ios_audio_transcription_subtitles_vod_enabled"]) {
        return [BHTSettings boolForKey:@"disable_video_captions"] ? @NO : nil;
    }

    // Custom navigation: per-panel tab gates, forced on so every panel exists for
    // the editor to offer. The tab bar hook keeps them out of the bar and the
    // dash spoof (below) keeps the panels only unlocked here out of the side
    // drawer.
    if ([key isEqualToString:@"ios_tab_bar_default_show_profile"] ||
        [key isEqualToString:@"ios_tab_bar_default_show_communities"]) {
        return @YES;
    }

    if ([key isEqualToString:
                 @"home_timeline_foreground_refresh_min_background_seconds"]) {
        return [BHTSettings boolForKey:@"no_focus_lost"] ? @(315360000.0) : nil;
    }

    // Communities, Spaces, News and Grok are enabled outright for every account.
    if ([key isEqualToString:@"ai_trends_ios_enable_news_tab"] ||
        [key isEqualToString:@"voice_rooms_consumption_enabled"] ||
        [key isEqualToString:@"communities_enable_explore_tab"] ||
        [key isEqualToString:@"subscriptions_inapp_grok"]) {
        return @YES;
    }

    // The Media tab reads its switch as an integer and shows on this sentinel.
    if ([key isEqualToString:@"media_tab_enabled"]) {
        return @99;
    }

    if ([key isEqualToString:@"grok_ios_grok_bot_upsells_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_sidebar_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_home_header_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_home_hero_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_preset_enabled"] ||
        [key isEqualToString:@"grok_ios_grok_bot_tab_icon_enabled"]) {
        return @NO;
    }

    // 0 hides the Communities tab, 1 is contextual-only; anything else shows it.
    if ([key isEqualToString:@"c9s_tab_visibility"]) {
        return @2;
    }

    if (!ReportGenuineTabGates) {
        if ([key isEqualToString:@"subscriptions_premium_hub_enabled"] ||
            [key isEqualToString:@"recruiting_global_jobs_hub_enabled"]) {
            return @YES;
        }
    }

    // The Connect tab stays on its native gate (fresh accounts only): its drawer
    // row doesn't consult the tab bar, so forcing it would grow a row that can't
    // be hidden.

    // In-app article webview
    if ([key isEqualToString:@"ios_in_app_article_webview_enabled"]) {
        return @([BHTSettings boolForKey:@"new_inapp_webview"]);
    }

    // A negative threshold disables immersive auto-advance and removes its row
    // from the player's settings sheet.
    if ([key
            isEqualToString:@"immersive_video_auto_advance_duration_threshold"]) {
        return [BHTSettings boolForKey:@"disable_immersive_scroll"] ? @(-1) : nil;
    }

    // Reply downvote (dislike) button
    if ([key isEqualToString:@"conversational_replies_ios_downvote_enabled"]) {
        return [BHTSettings boolForKey:@"hide_downvote_button"] ? @NO : nil;
    }

    if ([key isEqualToString:@"ssp_ads_spotlight"] ||
        [key isEqualToString:@"ssp_ads_spotlight_client_only_integration"] ||
        [key isEqualToString:
                 @"ssp_ads_spotlight_client_only_integration_preload"] ||
        [key isEqualToString:@"ssp_ads_home_enabled"] ||
        [key isEqualToString:@"ssp_ads_home_client_only_integration"] ||
        [key isEqualToString:@"ssp_ads_profile"] ||
        [key isEqualToString:
                 @"ssp_ads_profile_client_only_integration_enabled"] ||
        [key isEqualToString:@"ssp_ads_immersive"] ||
        [key isEqualToString:@"ssp_ads_immersive_client_only_integration"] ||
        [key isEqualToString:@"ssp_ads_tweet_details"] ||
        [key isEqualToString:
                 @"ssp_ads_tweet_details_client_only_integration"]) {
        return [BHTSettings boolForKey:@"hide_promoted"] ? @NO : nil;
    }

    // Reactive blending: likes and follows make the timeline request fresh
    // who-to-follow suggestions and splice them in; this switch turns it off.
    if ([key isEqualToString:@"wtf_device_follow_nudge_turn_off_reactive_blending_enabled"]) {
        return [BHTSettings boolForKey:@"hide_who_to_follow"] ? @YES : nil;
    }

    // Premium features gate on subscriptions_enabled || (gating bypass && premium
    // tier).
    if ([key isEqualToString:@"subscriptions_gating_bypass"]) {
        return @YES;
    }

    // Premium / verification upsells. Not all gate on !isPremiumTierUser, so
    // every upsell surface present in 12.3 is disabled here.
    if ([key isEqualToString:@"ios_profile_analytics_upsell_enabled"] ||
        [key isEqualToString:@"ios_profile_analytics_upsell_possible_enabled"] ||
        [key isEqualToString:@"ios_profile_upgrade_upsell_enabled"] ||
        [key isEqualToString:@"ios_profile_upgrade_upsell_swapper_enabled"] ||
        [key isEqualToString:@"ios_profile_visitor_upsell_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_get_verified_profile"] ||
        [key isEqualToString:@"subscriptions_upsells_reply_boost_enabled"] ||
        [key
            isEqualToString:@"subscriptions_upsells_reply_boost_popup_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_post_analytics_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_creator_support_post_"
                             @"conversation_enabled"] ||
        [key isEqualToString:@"longform_notetweets_composer_upsell_enabled"] ||
        [key isEqualToString:
                 @"longform_notetweets_composer_auto_upsell_enabled"] ||
        [key isEqualToString:@"subscriptions_cta_on_replies_enabled"] ||
        [key isEqualToString:@"super_follow_upsell_sticky_button_enabled"] ||
        [key isEqualToString:@"subscriptions_new_paywall_enabled"] ||
        [key isEqualToString:@"subscriptions_offers_promotional_enabled"] ||
        [key isEqualToString:@"subscriptions_gifting_premium_enabled"] ||
        [key isEqualToString:
                 @"subscriptions_gifting_premium_intro_copy_enabled"] ||
        [key isEqualToString:
                 @"subscriptions_ios_download_to_offline_upsell_enabled"] ||
        [key isEqualToString:
                 @"ios_notifications_blue_verified_introductory_offer_visible"] ||
        [key isEqualToString:@"ios_notifications_blue_verified_introductory_"
                             @"offer_prefix_visible"] ||
        [key isEqualToString:@"dash_items_download_grok_enabled"]) {
        return @NO;
    }

    // Boost (quick promote) button and its upsells. Each placement reads its own
    // switch rather than the root one, so all of them are disabled.
    if ([key isEqualToString:@"ios_tweet_promote_button_enabled"] ||
        [key isEqualToString:@"ios_tweet_promote_button_timeline_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_tweet_composer_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_overflow_menu_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_focal_top_toolbar_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_focal_bottom_toolbar_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_focal_top_analytics_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_post_analytics_enabled"] ||
        [key
            isEqualToString:
                @"ios_tweet_promote_button_boost_again_in_top_toolbar_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_sent_tweet_toast_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_third_party_boost_enabled"] ||
        [key isEqualToString:@"thirdparty_boost_author_view_button_enabled"]) {
        return @NO;
    }

    // The Premium settings row is handled in the
    // -isSubscriptionsSettingsItemEnabledWithProvider: hook. Creator purchases
    // and the subscriber-only profile tab already gate on real creator
    // eligibility, which the forced tier never affects.

    // Creator Studio / Monetization entries gate purely on these switches with no
    // premium check, so follow the genuine status: a real subscriber keeps them
    // while the spoof hides them.
    if ([key isEqualToString:@"creator_studio_nav_enabled"] ||
        [key isEqualToString:@"creator_monetization_dashboard_enabled"]) {
        if (!AccountIsGenuinelyPremium()) {
            return @NO;
        }
    }

    return nil;
}

// Every feature switch facade bottoms out in TFSFeatureSwitches, but instances
// can be wrapped in TFSInstrumentedFeatureSwitches, which implements its own
// typed getters, so both classes need the same hooks.

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

// Sets the scroll indicator in -[TFNDataViewController loadView]; the read
// bypasses the boolForKey: funnels above via a Swift access-once provider.
+ (BOOL)isShowsVerticalScrollIndicatorEnabled {
    return [BHTSettings boolForKey:@"show_scroll_indicator"] ? YES : %orig;
}

// Premium row in Settings. Its gate (subscriptions_enabled || gating_bypass &&
// isPremiumTierUser) is on for everyone as an upsell, so %orig can't hide
// it — short-circuit to NO unless the account (the provider) is genuinely
// premium.
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

// Custom navigation: tab gates read as typed accessors instead of through the
// keyed funnels, forced on like the keyed gates so their panels' entries build.
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

// Video downloads are likewise enabled outright for every account.
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

// API commands copy this off their context when building requests.
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

// Custom navigation: the Money tab's gate, granted per account/region by the
// server, forced on like the switch-keyed tab gates so the panel's entry
// builds.
- (BOOL)canAccessXPayments {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

%end

// MARK: - Genuine subscription status

// A few paths report subscription status outward (to marketing) or expose real
// subscription management; run them against the genuine status so a forced
// unlock is never announced as premium.

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

// Opens the real subscription management flow; its premium check should see the
// genuine status so a forced unlock stops here.
- (void)showPremiumHubManageSubscriptionWithSource:(NSInteger)source
                                    withCompletion:(id)completion {
    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    %orig;
    ReportGenuineSubscription = saved;
}

%end

%hook T1ProfileSummaryView

// The "under review" prompt shows for a verified-premium user not yet
// blue-verified — a state the forced tier fabricates for a non-subscriber, so
// read it against the genuine status.
- (BOOL)shouldShowUnderReviewButton {
    BOOL saved = ReportGenuineSubscription;
    ReportGenuineSubscription = YES;
    BOOL result = %orig;
    ReportGenuineSubscription = saved;
    return result;
}

%end

// MARK: - Custom navigation - genuine panel availability

// Whether a panel would be tab-eligible without the forced gates: the tab bar
// editor only offers genuine panels, and the dash spoof keeps the rest out of
// the drawer.

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
        default: // Panels the app builds, or the unlock enables, for everyone
            return YES;
    }
}

// MARK: - Custom navigation - side drawer rows

// The drawer builds a row for each panel absent from the tab bar, reading a
// snapshot taken in updateVisiblePanelIDs. Extra panels are injected only
// there, scoped by a flag — other visiblePanelIDs readers must see the real tab
// state. Premium is claimed for a non-premium account, for whom it's just an
// upsell.

static __thread BOOL DashPanelIDQuery = NO;

%hook T1DashContentController

- (void)updateVisiblePanelIDs {
    DashPanelIDQuery = YES;
    %orig;
    DashPanelIDQuery = NO;
}

%end

%hook T1TabbedAppNavigationViewController

// +[T1PanelIdentity iconImageNameForPanelID:] has the panel IDs
- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation {
    NSArray* panelIDs = %orig;
    if (!DashPanelIDQuery) {
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

    return spoofed;
}

%end

// MARK: - Grok creation - photo editor

// The photo editor's Edit with Grok entry has no feature switch of its own;
// both delegates hardcode YES.

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

%end

%hook HFHealthSafetyFeature

+ (BOOL)isTweetMedialInterstitialEnabled:(id)featureSwitches {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
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
