#import "Timeline.h"
#import "../Ads/Ads.h"

// MARK: - Hide "Discover more", who-to-follow and prompts

%hook T1ConversationContainerViewController

- (id)initWithAccount:(id)account
                         statusID:(long long)statusID
          statusNavigationContext:(id)statusNavigationContext
                    scribeContext:(id)scribeContext
         sourceNavigationMetadata:(id)sourceNavigationMetadata
       overrideNavigationMetadata:(id)overrideNavigationMetadata
      shouldIncludeReferrerParams:(BOOL)shouldIncludeReferrerParams
    shouldStartQuickPromoteOnOpen:(BOOL)shouldStartQuickPromoteOnOpen
                excludedStatusIDs:(id)excludedStatusIDs {
    id conversation = %orig(account, statusID, statusNavigationContext, scribeContext,
                                sourceNavigationMetadata, overrideNavigationMetadata,
                                shouldIncludeReferrerParams, shouldStartQuickPromoteOnOpen,
                                excludedStatusIDs);
    if (conversation && NavigationMetadataIsFromProfile(sourceNavigationMetadata)) {
        objc_setAssociatedObject(conversation, ConversationOpenedFromProfileKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return conversation;
}

- (id)initWithAccount:(id)account
                        viewModel:(id)viewModel
          statusNavigationContext:(id)statusNavigationContext
                    scribeContext:(id)scribeContext
         sourceNavigationMetadata:(id)sourceNavigationMetadata
       overrideNavigationMetadata:(id)overrideNavigationMetadata
      shouldIncludeReferrerParams:(BOOL)shouldIncludeReferrerParams
    shouldNotifyDisplayLatestEdit:(BOOL)shouldNotifyDisplayLatestEdit
    shouldStartQuickPromoteOnOpen:(BOOL)shouldStartQuickPromoteOnOpen
                excludedStatusIDs:(id)excludedStatusIDs {
    id conversation = %orig(account, viewModel, statusNavigationContext, scribeContext,
                                sourceNavigationMetadata, overrideNavigationMetadata,
                                shouldIncludeReferrerParams, shouldNotifyDisplayLatestEdit,
                                shouldStartQuickPromoteOnOpen, excludedStatusIDs);
    if (conversation && NavigationMetadataIsFromProfile(sourceNavigationMetadata)) {
        objc_setAssociatedObject(conversation, ConversationOpenedFromProfileKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return conversation;
}

%end

%hook T1EditHistoryViewControllerFactory

+ (id)viewControllerWithAccount:(id)account
                        tweetID:(unsigned long long)tweetID
                  scribeContext:(id)scribeContext {
    id viewController = %orig;
    if (viewController) {
        objc_setAssociatedObject(viewController, EditHistoryViewControllerKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return viewController;
}

%end

@implementation BHTimelineFilterContext

+ (instancetype)contextForDataViewController:(TFNItemsDataViewController*)dataViewController {
    BHTimelineFilterContext* context = [self new];

    context.inConversation =
        IsInHierarchyOfClass(dataViewController, @"T1ConversationContainerViewController");
    context.inProfile = IsInHierarchyOfClass(dataViewController, @"T1ProfileViewController");
    context.openedFromProfile = IsInProfileOriginConversation(dataViewController);
    context.inSearch = IsInHierarchyOfClass(dataViewController, @"TTSSearchContainerViewControllerV2") || IsInHierarchyOfClass(dataViewController, @"TTSSearchContainerViewController");
    context.inEditHistory = IsInEditHistory(dataViewController);
    context.inNotifications = IsInHierarchyOfClass(dataViewController, @"T1NotificationsViewController");

    context.hideWhoToFollow = [BHTSettings boolForKey:@"hide_who_to_follow"];
    context.hidePrompts = [BHTSettings boolForKey:@"hide_timeline_prompts"];
    context.hideVerified = [BHTSettings boolForKey:@"hide_verified_tweets"] &&
                           !context.inProfile && !context.inSearch && !context.inEditHistory;
    context.hideBlockedRetweets = [BHTSettings boolForKey:@"hide_blocked_retweets"];
    BOOL inPostInteractions =
        IsInHierarchyOfClass(dataViewController, @"T1PostInteractionsViewController");
    BOOL openedTweetFromProfile = context.inProfile || context.openedFromProfile;
    context.hideQuoteTweets = [BHTSettings boolForKey:@"hide_quote_tweets"] &&
                              !inPostInteractions && !openedTweetFromProfile;
    context.hideRetweets = [BHTSettings boolForKey:@"hide_retweets"] &&
                           !inPostInteractions && !openedTweetFromProfile;
    context.hideAITweets = [BHTSettings boolForKey:@"hide_ai_tweets"] && !openedTweetFromProfile;
    context.hidePaidTweets = [BHTSettings boolForKey:@"hide_paid_tweets"] && !openedTweetFromProfile;

    return context;
}

- (BOOL)shouldFilter {
    return self.hideWhoToFollow || self.hidePrompts || self.hideVerified ||
           self.hideAITweets || self.hidePaidTweets || self.hideQuoteTweets || self.hideRetweets || self.hideBlockedRetweets || self.inConversation;
}

- (void)resolveConversationLookupsInSections:(NSArray*)sections {
    if (!self.hideVerified || !self.inConversation) {
        self.conversationRootUserID = 0;
        self.authorRepliedToUserIDs = nil;
        return;
    }

    self.conversationRootUserID = ConversationRootUserID(sections);
    self.authorRepliedToUserIDs =
        ConversationAuthorRepliedToUserIDs(sections, self.conversationRootUserID);
}

- (BOOL)isEqualToContext:(BHTimelineFilterContext*)other {
    if (!other) {
        return NO;
    }

    return self.hideWhoToFollow == other.hideWhoToFollow &&
           self.hidePrompts == other.hidePrompts && self.hideVerified == other.hideVerified &&
           self.hideBlockedRetweets == other.hideBlockedRetweets &&
           self.inConversation == other.inConversation && self.inProfile == other.inProfile &&
           self.openedFromProfile == other.openedFromProfile &&
           self.inSearch == other.inSearch &&
           self.hideQuoteTweets == other.hideQuoteTweets &&
           self.hideRetweets == other.hideRetweets &&
           self.conversationRootUserID == other.conversationRootUserID &&
           self.inEditHistory == other.inEditHistory &&
           self.inNotifications == other.inNotifications &&
           self.hideAITweets == other.hideAITweets &&
           self.hidePaidTweets == other.hidePaidTweets &&
           (self.authorRepliedToUserIDs == other.authorRepliedToUserIDs ||
            [self.authorRepliedToUserIDs isEqualToSet:other.authorRepliedToUserIDs]);
}

@end

// MARK: - Videos for you module

%hook TNLResponseInfo

- (instancetype)initWithFinalURLRequest:(NSURLRequest*)request
                            URLResponse:(NSURLResponse*)response
                                 source:(NSInteger)source
                                   data:(NSData*)data
                     temporarySavedFile:(id)temporarySavedFile {
    if ([BHTSettings boolForKey:@"hide_videos_for_you"] && data &&
        IsGraphQLResponse(request.URL)) {
        NSData* marker = [@"video-carousel-" dataUsingEncoding:NSUTF8StringEncoding];
        if ([data rangeOfData:marker options:0 range:NSMakeRange(0, data.length)].location !=
            NSNotFound) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            BOOL removed = NO;
            id filtered = json ? RemoveVideoCarouselEntries(json, &removed) : nil;
            if (removed) {
                data = [NSJSONSerialization dataWithJSONObject:filtered options:0 error:nil] ?: data;
            }
        }
    }

    return %orig(request, response, source, data, temporarySavedFile);
}

%end

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    sections = FilteredTimelineSections(self, sections);
    %orig(FilteredSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    sections = FilteredTimelineSections(self, sections);
    %orig(FilteredSections(self, sections), identifiers, animation, completion);
}

%end
