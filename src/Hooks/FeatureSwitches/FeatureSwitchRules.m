#import "FeatureSwitchRules.h"

// Rules are evaluated in order. nil means keep the app's original value.
// Setting rules read the preference on every lookup, so changes apply live.
NSArray<BHTFeatureSwitchRule*>* BHTFeatureSwitchRules(void) {
    static NSArray<BHTFeatureSwitchRule*>* rules;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rules = @[

            // Custom timelines overrides
            BHTSettingSwitches(@[
                @"hometimeline_pinned_tabs_topics_enabled",
                @"hometimeline_pinned_tabs_generic_timelines_enabled",
                @"hometimeline_pinned_tabs_sticky_warm_start_enabled",
                @"super_follow_subscriptions_home_timeline_tab_sticky_enabled",
            ],
                               @"hide_custom_timelines", @NO, @YES),

            // Keeps the selected timeline tab across sessions.
            BHTFixedSwitches(@[
                @"home_timeline_non_sticky_tab_on_new_session_enabled",
            ],
                             @NO),
            BHTSettingSwitches(@[
                @"hometimeline_pinned_tabs_limit",
                @"hometimeline_pinned_tabs_management_pinnedsection_inline_limit",
                @"hometimeline_pinned_tabs_management_topics_inline_limit",
            ],
                               @"hide_custom_timelines", @0, @100),

            // Gates the add-tab (+) accessory button on the home tab bar.
            BHTSettingSwitches(@[
                @"hometimeline_pinned_tabs_pinned_trailing_accessory_enabled",
            ],
                               @"hide_custom_timelines", @NO, nil),

            // Restore the animated launch screen (AppLifecycle.x strips its X-shaped
            // reveal mask)
            BHTFixedSwitches(@[
                @"app_launch_animated_launch_screen_enabled",
            ],
                             @YES),

            // Grok translations
            BHTFixedSwitches(@[
                @"grok_translations_bio_inline_translation_is_enabled",
                @"grok_translations_bio_translation_is_enabled",
                @"grok_translations_post_inline_translation_is_enabled",
                @"grok_translations_post_translation_is_enabled",
                @"grok_translations_community_note_translation_is_enabled",
                @"grok_translations_poll_translation_is_enabled",
            ],
                             @YES),

            // Checked before the per-language preference, so turning these off stops all
            // auto translation while manual translate stays.
            BHTSettingSwitches(@[
                @"grok_translations_post_auto_translation_is_enabled",
                @"grok_translations_bio_auto_translation_is_enabled",
                @"grok_translations_community_note_auto_translation_is_enabled",
                @"grok_translations_notification_auto_translation_is_enabled",
                @"grok_translations_immersive_auto_translate_is_enabled",
            ],
                               @"disable_auto_translate", @NO, nil),

            // Grok buttons. These two Ask Grok keys were forced YES by the first
            // matching rule; later conflicting NO entries were unreachable.
            BHTFixedSwitches(@[
                @"grok_ask_grok_button_under_post_focal_enabled",
                @"grok_ask_grok_button_under_post_preview_enabled",
            ],
                             @YES),
            BHTSettingSwitches(@[
                @"grok_edit_with_grok_button_under_post_focal_enabled",
                @"grok_edit_with_grok_button_under_post_preview_enabled",
            ],
                               @"hide_grok_create", @0, @1),

            // Grok creation surfaces: composer buttons, imagine menus and CTAs, Edit with
            // Grok on photo posts, and the immersive player's create-your-own button.
            BHTSettingSwitches(@[
                @"ios_composer_grok_button_enabled",
                @"grok_imagine_composer_enabled",
                @"grok_composer_imagine_is_enabled",
                @"grok_composer_attachment_imagine_menu_is_enabled",
                @"grok_timeline_preview_imagine_menu_is_enabled",
                @"grok_timeline_video_imagine_menu_is_enabled",
                @"grok_timeline_slideshow_imagine_menu_is_enabled",
                @"grok_ios_edit_photo_post_button_enabled",
                @"grok_ios_imagine_cta_focal_enabled",
                @"grok_ios_imagine_cta_reply_enabled",
                @"grok_ios_imagine_cta_timeline_enabled",
                @"grok_ios_imagine_cta_profile_enabled",
                @"grok_immersive_create_own_button_enabled",
            ],
                               @"hide_grok_create", @NO, nil),

            // Disguised switch family for the Grok edit-photo and create-own buttons,
            // read only by Grok.GrokFeatureAccess.
            BHTPatternSwitches(@"ios_button_layout_fix", @"_enabled", @"hide_grok_create", @NO, nil),

            // Grok analyze: every tweet-side show decision gates on this backend switch
            // before consulting the per-tweet flag.
            BHTSettingSwitches(@[
                @"grok_ios_author_view_analyze_button_via_backend_enabled",
            ],
                               @"hide_grok_analyze", @NO, nil),

            // The profile header's analyze (summary) button bottoms out in this switch on
            // both header variants, one of which reads it through a direct Swift call.
            BHTSettingSwitches(@[
                @"grok_ios_profile_summary_enabled",
            ],
                               @"hide_grok_analyze", @0, @1),
            BHTFixedSwitches(@[
                @"grok_ios_grok_bot_upsells_enabled",
                @"grok_ios_grok_bot_sidebar_enabled",
                @"grok_ios_grok_bot_home_header_enabled",
                @"grok_ios_grok_bot_home_hero_enabled",
                @"grok_ios_grok_bot_preset_enabled",
                @"grok_ios_grok_bot_tab_icon_enabled",
            ],
                             @NO),

            // Session token appended to shared/copied links (&t=)
            BHTFixedSwitches(@[
                @"rehire_share_update_url_enabled",
            ],
                             @NO),

            // Click IDs on promoted links, and loading card links in the background
            // before they're tapped (LinkTracking.x).
            BHTSettingSwitches(@[
                @"ad_formats_click_id_enabled",
                @"wcl_unified_cards_likely_open_link_prefetch_enabled",
            ],
                               @"block_link_tracking", @NO, nil),

            // The profile hooks build on the classic header; the header rework
            // replaces the action-buttons row with a separate catalog system.
            BHTFixedSwitches(@[
                @"ios_profile_redesign_header_rework_enabled",
            ],
                             @NO),
            BHTFixedSwitches(@[
                @"xchat_ask_grok_enabled",
                @"grok_explain_text_selection_ask_grok_enabled",
            ],
                             @NO),
            BHTSettingSwitches(@[
                @"post_about_hide_grok_pills_enabled",
            ],
                               @"hide_grok_analyze", @YES, @NO),
            BHTFixedSwitches(@[
                @"ios_settings_redesign_enabled",
            ],
                             @YES),

            // Profile tabs
            BHTSettingSwitches(@[
                @"articles_timeline_profile_tab_enabled",
            ],
                               @"disable_articles", @0, @1),
            BHTSettingSwitches(@[
                @"highlights_tweets_tab_ui_enabled",
            ],
                               @"disable_highlights", @0, @1),

            // Age verification bypass
            BHTPatternSwitches(@"ios_age_assurance", nil, @"bypass_age_verification", @NO, nil),
            BHTSettingSwitches(@[
                @"grok_settings_age_restriction_enabled",
            ],
                               @"bypass_age_verification", @NO, nil),

            // Conversation / tweet detail
            BHTSettingSwitches(@[
                @"reply_sorting_enabled",
            ],
                               @"reply_sorting", @0, @1),
            BHTFixedSwitches(@[
                @"ios_tweet_detail_overflow_in_navigation_enabled",
            ],
                             @NO),
            BHTFixedSwitches(@[
                @"ios_ipad_phone_navigation_enabled",
            ],
                             @YES),
            BHTSettingSwitches(@[
                @"ios_tweet_detail_conversation_context_removal_enabled",
            ],
                               @"restore_reply_context", @0, @1),
            BHTSettingSwitches(@[
                @"ios_ui_multi_media_carousel_avatar_avoidance_enabled",
                @"ios_ui_multi_media_carousel_enabled",
                @"ios_ui_quote_tweet_multi_media_carousel_enabled",
            ],
                               @"disable_media_carousel", @NO, nil),
            BHTFixedSwitches(@[
                @"ios_liquid_glass_redesign_quick_composer_enabled",
            ],
                             @NO),

            BHTPatternSwitches(@"ios_liquid_glass", nil, @"liquid_glass", @YES, nil),
            BHTSettingSwitches(@[
                @"xchat_liquid_glass_convo_header_enabled",
            ],
                               @"liquid_glass", @YES, nil),

            // Video captions
            BHTSettingSwitches(@[
                @"ios_tav_default_closed_captions_enabled",
                @"ios_audio_transcription_subtitles_vod_enabled",
            ],
                               @"disable_video_captions", @NO, nil),
            BHTFixedSwitches(@[
                @"subscriptions_feature_1008",
            ],
                             @YES),
            BHTSettingSwitches(@[
                @"ios_alert_block_user_enabled",
                @"ios_alert_mute_user_enabled",
            ],
                               @"fast_block", @NO, nil),

            // Custom navigation: per-panel tab gates, forced on so every panel exists for
            // the editor to offer. The tab bar hook keeps them out of the bar and the
            // dash spoof (below) keeps the panels only unlocked here out of the side
            // drawer.
            BHTFixedSwitches(@[
                @"ios_tab_bar_default_show_profile",
                @"ios_tab_bar_default_show_communities",
            ],
                             @YES),
            BHTSettingSwitches(@[
                @"home_timeline_foreground_refresh_min_background_seconds",
            ],
                               @"no_focus_lost", @(315360000.0), nil),

            // Communities, Spaces, News and Grok are enabled outright for every account.
            BHTFixedSwitches(@[
                @"ai_trends_ios_enable_news_tab",
                @"voice_rooms_consumption_enabled",
                @"communities_enable_explore_tab",
                @"subscriptions_inapp_grok",
            ],
                             @YES),

            // The Media tab reads its switch as an integer and shows on this sentinel.
            BHTFixedSwitches(@[
                @"media_tab_enabled",
            ],
                             @99),

            // 0 hides the Communities tab, 1 is contextual-only; anything else shows it.
            BHTFixedSwitches(@[
                @"c9s_tab_visibility",
            ],
                             @2),
            BHTTabGateSwitches(@[
                @"subscriptions_premium_hub_enabled",
                @"recruiting_global_jobs_hub_enabled",
            ]),

            // The Connect tab stays on its native gate (fresh accounts only): its drawer
            // row doesn't consult the tab bar, so forcing it would grow a row that can't
            // be hidden.
            // In-app article webview
            BHTSettingSwitches(@[
                @"ios_in_app_article_webview_enabled",
            ],
                               @"new_inapp_webview", @YES, @NO),

            // A negative threshold disables immersive auto-advance and removes its row
            // from the player's settings sheet.
            BHTSettingSwitches(@[
                @"immersive_video_auto_advance_duration_threshold",
            ],
                               @"disable_immersive_scroll", @(-1), nil),

            // Reply downvote (dislike) button
            BHTSettingSwitches(@[
                @"conversational_replies_ios_downvote_enabled",
            ],
                               @"hide_downvote_button", @NO, nil),
            BHTSettingSwitches(@[
                @"ssp_ads_spotlight",
                @"ssp_ads_spotlight_client_only_integration",
                @"ssp_ads_spotlight_client_only_integration_preload",
                @"ssp_ads_home_enabled",
                @"ssp_ads_home_client_only_integration",
                @"ssp_ads_profile",
                @"ssp_ads_profile_client_only_integration_enabled",
                @"ssp_ads_immersive",
                @"ssp_ads_immersive_client_only_integration",
                @"ssp_ads_tweet_details",
                @"ssp_ads_tweet_details_client_only_integration",
            ],
                               @"hide_promoted", @NO, nil),

            // Reactive blending: likes and follows make the timeline request fresh
            // who-to-follow suggestions and splice them in; this switch turns it off.
            BHTSettingSwitches(@[
                @"wtf_device_follow_nudge_turn_off_reactive_blending_enabled",
            ],
                               @"hide_who_to_follow", @YES, nil),

            // Premium features gate on subscriptions_enabled || (gating bypass && premium
            // tier).
            BHTFixedSwitches(@[
                @"subscriptions_gating_bypass",
            ],
                             @YES),
            BHTBrandedSwitches(@[
                @"ios_home_timeline_logo_pull_to_refresh_enabled",
            ],
                               @NO, @YES),

            // Premium / verification upsells. Not all gate on !isPremiumTierUser, so
            // every upsell surface present in 12.3 is disabled here.
            BHTFixedSwitches(@[
                @"ios_profile_analytics_upsell_enabled",
                @"ios_profile_analytics_upsell_possible_enabled",
                @"ios_profile_upgrade_upsell_enabled",
                @"ios_profile_upgrade_upsell_swapper_enabled",
                @"ios_profile_visitor_upsell_enabled",
                @"subscriptions_upsells_get_verified_profile",
                @"subscriptions_upsells_reply_boost_enabled",
                @"subscriptions_upsells_reply_boost_popup_enabled",
                @"subscriptions_upsells_post_analytics_enabled",
                @"subscriptions_upsells_creator_support_post_conversation_enabled",
                @"longform_notetweets_composer_upsell_enabled",
                @"longform_notetweets_composer_auto_upsell_enabled",
                @"subscriptions_cta_on_replies_enabled",
                @"super_follow_upsell_sticky_button_enabled",
                @"subscriptions_new_paywall_enabled",
                @"subscriptions_offers_promotional_enabled",
                @"subscriptions_gifting_premium_enabled",
                @"subscriptions_gifting_premium_intro_copy_enabled",
                @"subscriptions_ios_download_to_offline_upsell_enabled",
                @"ios_notifications_blue_verified_introductory_offer_visible",
                @"ios_notifications_blue_verified_introductory_offer_prefix_visible",
                @"dash_items_download_grok_enabled",
            ],
                             @NO),

            // Boost (quick promote) button and its upsells. Each placement reads its own
            // switch rather than the root one, so all of them are disabled.
            BHTFixedSwitches(@[
                @"ios_tweet_promote_button_enabled",
                @"ios_tweet_promote_button_timeline_enabled",
                @"ios_tweet_promote_button_in_tweet_composer_enabled",
                @"ios_tweet_promote_button_in_overflow_menu_enabled",
                @"ios_tweet_promote_button_in_focal_top_toolbar_enabled",
                @"ios_tweet_promote_button_in_focal_bottom_toolbar_enabled",
                @"ios_tweet_promote_button_in_focal_top_analytics_enabled",
                @"ios_tweet_promote_button_in_post_analytics_enabled",
                @"ios_tweet_promote_button_boost_again_in_top_toolbar_enabled",
                @"ios_tweet_promote_button_sent_tweet_toast_enabled",
                @"ios_tweet_promote_button_third_party_boost_enabled",
                @"thirdparty_boost_author_view_button_enabled",
            ],
                             @NO),

            // The Premium settings row is handled in the
            // -isSubscriptionsSettingsItemEnabledWithProvider: hook. Creator purchases
            // and the subscriber-only profile tab already gate on real creator
            // eligibility, which the forced tier never affects.
            // Creator Studio / Monetization entries gate purely on these switches with no
            // premium check, so follow the genuine status: a real subscriber keeps them
            // while the spoof hides them.
            BHTPremiumSwitches(@[
                @"creator_studio_nav_enabled",
                @"creator_monetization_dashboard_enabled",
            ]),
        ];
    });
    return rules;
}
