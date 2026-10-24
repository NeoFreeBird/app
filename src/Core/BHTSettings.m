//
//  BHTSettings.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Core/BHTSettings.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"

static NSDictionary<NSString*, NSDictionary*>* BHTSettingsPages(void) {
    static NSDictionary<NSString*, NSDictionary*>* pages;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pages = @{
            @"general": @{
                @"titleKey": @"MODERN_SETTINGS_LAYOUT_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_LAYOUT_SUBTITLE",
                @"settings": @[
                    @{@"key": @"padlock",
                      @"default": @NO},
                    @{@"key": @"hide_promoted",
                      @"default": @YES},
                    @{@"key": @"hide_premium_offer",
                      @"default": @YES},
                    @{@"key": @"no_tab_bar_hiding",
                      @"default": @YES},
                    @{@"key": @"disable_rtl",
                      @"default": @NO},
                    @{@"key": @"no_focus_lost",
                      @"default": @NO},
                    @{@"key": @"show_scroll_indicator",
                      @"default": @NO}
                ]
            },
            @"appearance": @{
                @"titleKey": @"MODERN_SETTINGS_APPEARANCE_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_APPEARANCE_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey": @"THEME_OPTION_TITLE",
                        @"action": @"showThemeViewController:",
                        @"type": @"button"
                    },
                    @{
                        @"titleKey": @"APP_ICON_TITLE",
                        @"action": @"showAppIconViewController:",
                        @"type": @"button"
                    },
                    @{
                        @"titleKey": @"CUSTOM_TAB_BAR_OPTION_TITLE",
                        @"action": @"showCustomTabBarVC:",
                        @"type": @"button"
                    },
                    @{@"key": @"tab_bar_theming",
                      @"default": @NO},
                    @{@"key": @"restore_tab_labels",
                      @"default": @NO},
                    @{@"key": @"enable_dim_theme",
                      @"default": @NO},
                    @{@"key": @"custom_fonts",
                      @"default": @NO},
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"regular_font_button",
                        @"titleKey": @"REGULAR_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showRegularFontPicker:",
                        @"prefKeyForSubtitle": @"bhtwitter_font_1",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE"
                    },
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"bold_font_button",
                        @"titleKey": @"BOLD_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showBoldFontPicker:",
                        @"prefKeyForSubtitle": @"bhtwitter_font_2",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE"
                    }
                ]
            },
            @"timelines": @{
                @"titleKey": @"MODERN_SETTINGS_TIMELINES_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_TIMELINES_SUBTITLE",
                @"settings": @[
                    @{@"key": @"hide_who_to_follow",
                      @"default": @YES},
                    @{@"key": @"hide_timeline_prompts",
                      @"default": @YES},
                    @{@"key": @"hide_videos_for_you",
                      @"default": @NO},
                    @{@"key": @"hide_spaces",
                      @"default": @NO},
                    @{@"key": @"hide_custom_timelines",
                      @"default": @NO},
                    @{@"key": @"show_quote_numbers",
                      @"default": @NO},
                    @{@"key": @"show_unrounded_quote_numbers",
                      @"parentKey": @"show_quote_numbers",
                      @"default": @NO},
                    @{@"key": @"hide_blocked_retweets",
                      @"default": @NO},
                    @{@"key": @"hide_tweet_button",
                      @"default": @NO},
                    @{@"key": @"hide_retweets",
                      @"default": @NO},
                    @{@"key": @"hide_quote_tweets",
                      @"default": @NO},
                    @{@"key": @"hide_verified_tweets",
                      @"default": @NO},
                    @{@"key": @"restore_refresh_sounds",
                      @"default": @YES}
                ]
            },
            @"grok": @{
                @"titleKey": @"MODERN_SETTINGS_GROK_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_GROK_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"hide_grok_analyze",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_sidebar",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_create",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_auto_translate",
                        @"default": @NO,
                        @"type": @"toggle"
                    }
                ]
            },
            @"media_downloads": @{
                @"titleKey": @"MODERN_SETTINGS_MEDIA_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_MEDIA_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"download_videos",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"download_highest_quality",
                        @"parentKey": @"download_videos",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"download_all_videos",
                        @"parentKey": @"download_videos",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{@"key": @"direct_save",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"key": @"disable_video_captions",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"auto_highest_load",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"force_tweet_full_frame",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"restore_video_timestamp",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_immersive_scroll",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_video_docking",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"tap_to_pause",
                        @"default": @NO,
                        @"type": @"toggle"
                    }
                ]
            },
            @"profiles": @{
                @"titleKey": @"MODERN_SETTINGS_PROFILES_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_PROFILES_SUBTITLE",
                @"settings": @[
                    @{@"key": @"follow_confirm",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"key": @"copy_profile_info",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"fast_block",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_articles",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_highlights",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_blue_verified",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_follow_button",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_message_button",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"show_unrounded_counts",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"restore_follow_button",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{@"key": @"square_avatars",
                      @"default": @NO,
                      @"type": @"toggle"}
                ]
            },
            @"chat": @{
                @"titleKey": @"MODERN_SETTINGS_CHAT_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_CHAT_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"hide_typing_indicator",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"download_voice_messages",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"block_screenshot_detection",
                        @"default": @NO,
                        @"type": @"toggle"
                    }
                ]
            },
            @"tweets": @{
                @"titleKey": @"MODERN_SETTINGS_TWEETS_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_TWEETS_SUBTITLE",
                @"settings": @[
                    @{
                        @"type": @"compactButton",
                        @"key": @"undo_tweet_timeout",
                        @"default": @10,
                        @"titleKey": @"UNDO_TWEET_TITLE",
                        @"action": @"showUndoTimeoutPicker:"
                    },
                    @{@"key": @"tweet_confirm",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"like_confirm",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"tweet_to_image",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"key": @"hide_view_count",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_bookmark_button",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_downvote_button",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"use_tenor_gifs",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_media_carousel",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_sensitive_tweet_warnings",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"show_poll_results",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"show_account_location",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"restore_tweet_labels",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"upload_full_hd_videos",
                        @"default": @NO,
                        @"type": @"toggle"
                    },
                    @{
                        @"type": @"compactButton",
                        @"titleKey": @"CUSTOM_SEND_SOUND_TITLE",
                        @"action": @"importTweetSound:",
                        @"prefKeyForSubtitle": @"custom_send_sound_name",
                        @"subtitleDefaultKey": @"CUSTOM_SEND_SOUND_DEFAULT"
                    },
                    @{
                        @"key": @"bypass_age_verification",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{@"key": @"reply_sorting",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"type": @"compactButton",
                        @"key": @"default_reply_sort",
                        @"default": @0,
                        @"titleKey": @"DEFAULT_REPLY_SORTING_TITLE",
                        @"action": @"showReplySortPicker:"
                    },
                    @{
                        @"key": @"restore_reply_context",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                ]
            },
            @"search": @{
                @"titleKey": @"MODERN_SETTINGS_SEARCH_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_SEARCH_SUBTITLE",
                @"settings": @[
                    @{@"key": @"no_history",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_trends",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"key": @"hide_trend_videos",
                        @"default": @NO,
                        @"type": @"toggle"
                    }
                ]
            },
            @"branding": @{
                @"titleKey": @"MODERN_SETTINGS_BRANDING_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_BRANDING_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"restore_twitter_names",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"refresh_pill_label",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"color_twitter_icon_in_top_bar",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"blue_launch_screen",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    }
                ]
            },
            @"presets": @{
                @"titleKey": @"MODERN_SETTINGS_PRESETS_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_PRESETS_SUBTITLE",
                @"settings": @[
                    @{
                        @"type": @"compactButton",
                        @"titleKey": @"SETTINGS_EXPORT_TITLE",
                        @"action": @"exportSettings:"
                    },
                    @{
                        @"type": @"compactButton",
                        @"titleKey": @"SETTINGS_IMPORT_TITLE",
                        @"action": @"importSettings:"
                    }
                ]
            },
            @"experimental": @{
                @"titleKey": @"MODERN_SETTINGS_EXPERIMENTAL_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_EXPERIMENTAL_SUBTITLE",
                @"settings": @[
                    @{@"key": @"reply_in_webview",
                      @"default": @NO,
                      @"type": @"toggle"}
                ]
            },
            @"web": @{
                @"titleKey": @"MODERN_SETTINGS_WEB_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_WEB_SUBTITLE",
                @"settings": @[
                    @{
                        @"type": @"compactButton",
                        @"key": @"sharing_domain",
                        @"action": @"showSharingDomainPrompt:",
                        @"prefKeyForSubtitle": @"sharing_domain",
                        @"subtitleDefault": @"x.com"
                    },
                    @{@"key": @"always_open_safari",
                      @"default": @NO},
                    // X's new article webview does not work under
                    // LiveContainer, so default it off there rather than
                    // forcing the switch on for every guest install.
                    @{@"key": @"new_inapp_webview",
                      @"default": @(![BHTManager isLiveContainer])},
                    @{@"key": @"block_link_tracking",
                      @"default": @YES},
                    @{@"key": @"strip_tracking_params",
                      @"default": @YES}
                ]
            },
            @"debug": @{
                @"titleKey": @"MODERN_SETTINGS_DEBUG_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_DEBUG_SUBTITLE",
                @"settings": @[
                    @{@"key": @"flex_twitter",
                      @"default": @NO,
                      @"type": @"toggle"}
                ]
            }
        };
    });
    return pages;
}

static NSDictionary<NSString*, NSDictionary*>* BHTSettingsIndex(void) {
    static NSDictionary<NSString*, NSDictionary*>* index;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString*, NSDictionary*>* map =
            [NSMutableDictionary dictionary];
        for (NSDictionary* page in BHTSettingsPages().allValues) {
            for (NSDictionary* setting in page[@"settings"]) {
                NSString* key = setting[@"key"];
                if (key) {
                    map[key] = setting;
                }
            }
        }
        index = [map copy];
    });
    return index;
}

@implementation BHTSettings

#pragma mark - Migration

// One-time migration of preferences saved under the old (inconsistent) key
// names to the normalised keys, so existing installs keep their settings.
+ (void)load {
    [self migrateUndoTweetToggle];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"nfb_key_migration_v1_done"]) {
        return;
    }

    NSDictionary<NSString*, NSString*>* renamedKeys = @{
        @"dis_rtl": @"disable_rtl",
        @"showScollIndicator": @"show_scroll_indicator",
        @"en_font": @"custom_fonts",
        @"dw_v": @"download_videos",
        @"video_layer_caption": @"disable_video_captions",
        @"autoHighestLoad": @"auto_highest_load",
        @"follow_con": @"follow_confirm",
        @"CopyProfileInfo": @"copy_profile_info",
        @"disableArticles": @"disable_articles",
        @"disableHighlights": @"disable_highlights",
        @"TweetToImage": @"tweet_to_image",
        @"like_con": @"like_confirm",
        @"tweet_con": @"tweet_confirm",
        @"disableSensitiveTweetWarnings": @"disable_sensitive_tweet_warnings",
        @"no_his": @"no_history",
        @"openInBrowser": @"always_open_safari",
        @"reply_sorting_enabled": @"reply_sorting",
        @"ios_in_app_article_webview_enabled": @"new_inapp_webview",
        @"tweet_url_host": @"sharing_domain",
    };

    // These old names double as Twitter's own feature-switch keys, so copy the
    // value across but leave the original in place rather than risk removing it.
    NSSet<NSString*>* sharedWithTwitter = [NSSet setWithArray:@[
        @"reply_sorting_enabled",
        @"ios_in_app_article_webview_enabled",
    ]];

    [renamedKeys enumerateKeysAndObjectsUsingBlock:^(
                     NSString* oldKey, NSString* newKey, BOOL* stop) {
        id value = [defaults objectForKey:oldKey];
        if (value == nil) {
            return;
        }
        if ([defaults objectForKey:newKey] == nil) {
            [defaults setObject:value forKey:newKey];
        }
        if (![sharedWithTwitter containsObject:oldKey]) {
            [defaults removeObjectForKey:oldKey];
        }
    }];

    [defaults setBool:YES forKey:@"nfb_key_migration_v1_done"];
}

// The Undo Tweet on/off toggle was merged into the timeout picker, where a
// timeout of 0 means off. Carry a prior "off" state across as a 0 timeout.
+ (void)migrateUndoTweetToggle {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"nfb_undo_timeout_migration_done"]) {
        return;
    }

    id oldToggle = [defaults objectForKey:@"undo_tweet"];
    if (oldToggle != nil && ![oldToggle boolValue] &&
        [defaults objectForKey:@"undo_tweet_timeout"] == nil) {
        [defaults setInteger:0 forKey:@"undo_tweet_timeout"];
    }
    [defaults removeObjectForKey:@"undo_tweet"];
    [defaults setBool:YES forKey:@"nfb_undo_timeout_migration_done"];
}

#pragma mark - Accessors

+ (NSArray<NSDictionary*>*)settingsForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"settings"] : nil;
}

+ (NSString*)titleKeyForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"titleKey"] : nil;
}

+ (NSString*)subtitleKeyForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"subtitleKey"] : nil;
}

+ (NSDictionary*)settingForKey:(NSString*)key {
    return key ? BHTSettingsIndex()[key] : nil;
}

// A row backs a preference when it carries a default (toggles and pickers) or
// renders a stored value as its subtitle (the font and sharing domain rows,
// whose own key is just a row identifier).
+ (NSArray<NSString*>*)allPreferenceKeys {
    static NSArray<NSString*>* keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableOrderedSet<NSString*>* collected = [NSMutableOrderedSet orderedSet];
        for (NSDictionary* page in BHTSettingsPages().allValues) {
            for (NSDictionary* setting in page[@"settings"]) {
                NSString* key = setting[@"key"];
                if (key && setting[@"default"]) {
                    [collected addObject:key];
                }
                NSString* subtitleKey = setting[@"prefKeyForSubtitle"];
                if (subtitleKey) {
                    [collected addObject:subtitleKey];
                }
            }
        }
        keys = [collected.array copy];
    });
    return keys;
}

+ (BOOL)boolForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value boolValue];
    }
    return [[self settingForKey:key][@"default"] boolValue];
}

+ (NSInteger)integerForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value integerValue];
    }
    return [[self settingForKey:key][@"default"] integerValue];
}

@end
