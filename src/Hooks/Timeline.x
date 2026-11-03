//
//  Timeline.x
//  NeoFreeBird
//

#import <string.h>
#import "HookHelpers.h"

// MARK: - Hide "Discover more", who-to-follow and prompts

// Resolves the class by name so mangled Swift names work; NSStringFromClass
// would only ever produce the demangled dotted form.
static BOOL IsInHierarchyOfClass(UIViewController* viewController, NSString* className) {
    Class targetClass = NSClassFromString(className);
    if (!targetClass) {
        return NO;
    }

    UIViewController* currentVC = viewController;

    while (currentVC) {
        if ([currentVC isKindOfClass:targetClass]) {
            return YES;
        }

        if (currentVC.parentViewController) {
            currentVC = currentVC.parentViewController;
        } else if (currentVC.navigationController) {
            currentVC = currentVC.navigationController;
        } else if (currentVC.presentingViewController) {
            currentVC = currentVC.presentingViewController;
        } else {
            break;
        }
    }

    return NO;
}

// Need to tag edit history since it reuses a generic class
static const void* EditHistoryViewControllerKey = &EditHistoryViewControllerKey;

static BOOL IsInEditHistory(UIViewController* viewController) {
    UIViewController* currentVC = viewController;

    while (currentVC) {
        if (objc_getAssociatedObject(currentVC, EditHistoryViewControllerKey)) {
            return YES;
        }

        currentVC = currentVC.parentViewController;
    }

    return NO;
}

static const void* ConversationOpenedFromProfileKey = &ConversationOpenedFromProfileKey;

static BOOL StringSuggestsProfile(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return NO;
    }

    return [[(NSString*)value lowercaseString] containsString:@"profile"];
}

static id ObjectForSelector(id object, SEL selector) {
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL NavigationMetadataIsFromProfile(id metadata) {
    if (!metadata) {
        return NO;
    }

    if ([metadata respondsToSelector:@selector(name)] &&
        StringSuggestsProfile(ObjectForSelector(metadata, @selector(name)))) {
        return YES;
    }

    id scribeContext = nil;
    if ([metadata respondsToSelector:@selector(sourceScribeContext)]) {
        scribeContext = ObjectForSelector(metadata, @selector(sourceScribeContext));
    }

    for (NSUInteger depth = 0; scribeContext && depth < 8; depth++) {
        NSArray<NSString*>* selectors = @[@"page", @"section", @"component", @"element"];
        for (NSString* selectorName in selectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([scribeContext respondsToSelector:selector] &&
                StringSuggestsProfile(ObjectForSelector(scribeContext, selector))) {
                return YES;
            }
        }

        if (![scribeContext respondsToSelector:@selector(sourceContext)]) {
            break;
        }
        scribeContext = ObjectForSelector(scribeContext, @selector(sourceContext));
    }

    return NO;
}

static BOOL IsInProfileOriginConversation(UIViewController* viewController) {
    UIViewController* currentVC = viewController;

    while (currentVC) {
        if (objc_getAssociatedObject(currentVC, ConversationOpenedFromProfileKey)) {
            return YES;
        }

        if (currentVC.parentViewController) {
            currentVC = currentVC.parentViewController;
        } else if (currentVC.navigationController) {
            currentVC = currentVC.navigationController;
        } else if (currentVC.presentingViewController) {
            currentVC = currentVC.presentingViewController;
        } else {
            break;
        }
    }

    return NO;
}

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

static NSString* ItemEntryID(id viewModel) {
    if (![viewModel respondsToSelector:@selector(entryID)]) {
        return nil;
    }

    NSString* entryID = [viewModel performSelector:@selector(entryID)];
    return [entryID isKindOfClass:[NSString class]] ? entryID : nil;
}

static NSString* ItemScribeComponent(id viewModel) {
    if (![viewModel respondsToSelector:@selector(scribeComponent)]) {
        return nil;
    }

    NSString* component = [viewModel performSelector:@selector(scribeComponent)];
    return [component isKindOfClass:[NSString class]] ? component : nil;
}

static BOOL ItemRespondsAndInvokesBOOL(id viewModel, SEL selector) {
    if (![viewModel respondsToSelector:selector]) {
        return NO;
    }

    return ((BOOL (*)(id, SEL))objc_msgSend)(viewModel, selector);
}

// Set when a reply is only on the feed because a followed account replied to
// someone else's tweet
static BOOL ItemIsReplyWithSocialContext(id viewModel) {
    return ItemRespondsAndInvokesBOOL(viewModel, @selector(isReplyAndShouldShowSocialContext));
}

static BOOL ItemIsConversationThreadReply(id viewModel) {
    return [ItemEntryID(viewModel) containsString:@"conversationthread"];
}

// The tweet's author and who it's directly replying to, for recognizing an
// exchange between the thread's own author and a verified user. Real user
// IDs are never 0, so that doubles as "unknown/unsupported".
static long long ItemRepresentedFromUserID(id viewModel) {
    SEL selector = @selector(representedFromUserID);
    if (![viewModel respondsToSelector:selector]) {
        return 0;
    }

    return ((long long (*)(id, SEL))objc_msgSend)(viewModel, selector);
}

static long long AdditionalItemRepresentedFromUserID(id viewModel) {
    SEL selector = @selector(fromUser);
    if (![viewModel respondsToSelector:selector]) {
        return 0;
    }

    // Get the userID NSInteger from the viewModel if the selector exists
    id fromUser = ((id (*)(id, SEL))objc_msgSend)(viewModel, selector);
    if (![fromUser respondsToSelector:@selector(userID)]) {
        return 0;
    }
    return ((long long (*)(id, SEL))objc_msgSend)(fromUser, @selector(userID));
}

static long long ItemInReplyToUserID(id viewModel) {
    SEL selector = @selector(inReplyToUserID);
    if (![viewModel respondsToSelector:selector]) {
        return 0;
    }

    return ((long long (*)(id, SEL))objc_msgSend)(viewModel, selector);
}

static long long CurrentAccountUserID(void) {
    Class hostClass = objc_getClass("T1HostViewController");
    if (!hostClass) {
        return 0;
    }

    id host = ((id (*)(id, SEL))objc_msgSend)(
        (id)hostClass, @selector(sharedHostViewController));
    if (![host respondsToSelector:@selector(currentAccount)]) {
        return 0;
    }

    id account = ((id (*)(id, SEL))objc_msgSend)(host, @selector(currentAccount));
    if (![account respondsToSelector:@selector(userID)]) {
        return 0;
    }

    return ((long long (*)(id, SEL))objc_msgSend)(account, @selector(userID));
}

// Twitter's *ByCurrentAccountState fields are a tri-state (0 unknown, 1 yes,
// 2 no); if follows still get hidden, flip this to the value logged for a
// known-followed account.
static const NSInteger kFollowedByCurrentAccountStateFollowing = 1;
static const NSInteger kBlockingCurrentAccountStateBlocking = 1;

static BOOL UserBlocksCurrentAccount(id user) {
    SEL relationshipSelector = @selector(relationship);
    if (![user respondsToSelector:relationshipSelector]) {
        return NO;
    }

    id relationship = ((id (*)(id, SEL))objc_msgSend)(user, relationshipSelector);
    SEL blockingSelector = @selector(blockingCurrentAccountState);
    if (![relationship respondsToSelector:blockingSelector]) {
        return NO;
    }

    NSInteger blockingState =
        ((NSInteger (*)(id, SEL))objc_msgSend)(relationship, blockingSelector);
    return blockingState == kBlockingCurrentAccountStateBlocking;
}

static BOOL ItemIsRetweetOfBlockingUser(id viewModel) {
    if (!ItemRespondsAndInvokesBOOL(viewModel, @selector(isRetweet))) {
        return NO;
    }

    SEL authorSelector = @selector(representedFromUser);
    if (![viewModel respondsToSelector:authorSelector]) {
        return NO;
    }

    return UserBlocksCurrentAccount(
        ((id (*)(id, SEL))objc_msgSend)(viewModel, authorSelector));
}

static BOOL ItemIsQuoteTweet(id viewModel) {
    if (!ItemRespondsAndInvokesBOOL(viewModel, @selector(isQuoteStatus))) {
        return NO;
    }

    long long currentAccountUserID = CurrentAccountUserID();
    long long representedFromUserID = AdditionalItemRepresentedFromUserID(viewModel);
    if (currentAccountUserID != 0 && representedFromUserID == currentAccountUserID) {
        return NO;
    }
    return YES;
}

static BOOL ItemIsRetweet(id viewModel) {
    if (!ItemRespondsAndInvokesBOOL(viewModel, @selector(isRetweet))) {
        return NO;
    }

    long long currentAccountUserID = CurrentAccountUserID();
    long long representedFromUserID = AdditionalItemRepresentedFromUserID(viewModel);
    if (currentAccountUserID != 0 && representedFromUserID == currentAccountUserID) {
        return NO;
    }

    return YES;
}

// Everything the per-item filters need to know about one section update: which
// hide toggles are on, which screen the timeline is being shown on, and the
// conversation lookups those two imply. Adding a filter or a surface means
// adding a property here, a line in +contextForDataViewController: and a line
// in -isEqualToContext:, instead of another argument threaded through every
// function in this section.
@interface BHTimelineFilterContext : NSObject

// Hide toggles, already resolved against the surface — hideVerified stays off
// in profiles and search, where seeing the account that was looked up is the
// whole point of being there.
@property (nonatomic) BOOL hideWhoToFollow;
@property (nonatomic) BOOL hidePrompts;
@property (nonatomic) BOOL hideVerified;
@property (nonatomic) BOOL hideQuoteTweets;
@property (nonatomic) BOOL hideRetweets;
@property (nonatomic) BOOL hideBlockedRetweets;

// Surfaces.
@property (nonatomic) BOOL inConversation;
@property (nonatomic) BOOL inProfile;
@property (nonatomic) BOOL openedFromProfile;
@property (nonatomic) BOOL inSearch;
@property (nonatomic) BOOL inEditHistory;

// Conversation lookups, filled in by -resolveConversationLookupsInSections:
// once per section update and only when hiding verified replies needs them.
@property (nonatomic) long long conversationRootUserID;
@property (nonatomic, copy) NSSet<NSNumber*>* authorRepliedToUserIDs;

// NO when nothing in this context can hide anything, so the sections can be
// handed back untouched.
@property (nonatomic, readonly) BOOL shouldFilter;

+ (instancetype)contextForDataViewController:(TFNItemsDataViewController*)dataViewController;
- (void)resolveConversationLookupsInSections:(NSArray*)sections;
- (BOOL)isEqualToContext:(BHTimelineFilterContext*)other;

@end

static BOOL BHShouldHideVerifiedItem(id viewModel, BHTimelineFilterContext* context) {
    SEL verifiedSelector = @selector(isFromUserVerified);
    if (![viewModel respondsToSelector:verifiedSelector]) {
        return NO;
    }

    BOOL verified = ((BOOL (*)(id, SEL))objc_msgSend)(viewModel, verifiedSelector);
    if (!verified) {
        return NO;
    }

    SEL bookmarkedSelector = @selector(displayAsBookmarked);
    if ([viewModel respondsToSelector:bookmarkedSelector]) {
        BOOL bookmarked = ((BOOL (*)(id, SEL))objc_msgSend)(viewModel, bookmarkedSelector);
        if (bookmarked) {
            return NO;
        }
    }

    if (context.inConversation) {
        if (!ItemIsConversationThreadReply(viewModel)) {
            return NO;
        }

        if (context.conversationRootUserID != 0) {
            long long repliedUserID = ItemRepresentedFromUserID(viewModel);

            BOOL isAuthorsOwnReply = repliedUserID == context.conversationRootUserID;
            BOOL authorRepliedToThisUser =
                [context.authorRepliedToUserIDs containsObject:@(repliedUserID)];
            if (isAuthorsOwnReply || authorRepliedToThisUser) {
                return NO;
            }
        }
    }

    if (!context.inConversation && ItemIsReplyWithSocialContext(viewModel)) {
        return NO;
    }

    SEL followStateSelector = @selector(representedFromUserFollowedByCurrentAccountState);
    if ([viewModel respondsToSelector:followStateSelector]) {
        NSInteger followState =
            ((NSInteger (*)(id, SEL))objc_msgSend)(viewModel, followStateSelector);
        if (followState == kFollowedByCurrentAccountStateFollowing) {
            return NO;
        }
    }

    return YES;
}

static BOOL ShouldHideTimelineItem(id item, BHTimelineFilterContext* context) {
    id viewModel = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([viewModel classForCoder]);

    if (context.hideVerified && BHShouldHideVerifiedItem(viewModel, context)) {
        return YES;
    }

    if (context.hideBlockedRetweets && ItemIsRetweetOfBlockingUser(viewModel)) {
        return YES;
    }

    if (context.hidePrompts && [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"]) {
        return YES;
    }

    if (context.hideWhoToFollow && [ItemScribeComponent(viewModel)
                                       isEqualToString:@"suggest_who_to_follow"]) {
        return YES;
    }

    if (context.hideWhoToFollow && context.inProfile &&
        [className isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
        return YES;
    }

    if (!context.inProfile && context.hideQuoteTweets && ItemIsQuoteTweet(viewModel) &&
        !ItemIsReplyWithSocialContext(viewModel)) {
        return YES;
    }

    if (!context.inProfile && context.hideRetweets && ItemIsRetweet(viewModel)) {
        return YES;
    }

    NSString* entryID = ItemEntryID(viewModel);

    if (!entryID) {
        return NO;
    }

    if (context.inConversation && [entryID hasPrefix:@"tweetdetailrelatedtweets"]) {
        return YES;
    }

    if (context.hideWhoToFollow && [entryID containsString:@"who-to-follow"]) {
        return YES;
    }

    return NO;
}

// Calling ShouldHideTimelineItem() for every item on every section update slows
// the app down a LOT, so verdicts are memoized by entry ID. They only hold for
// the context that produced them; a different context drops the whole cache.
static NSCache<NSString*, NSNumber*>* TimelineVerdictCacheForContext(
    BHTimelineFilterContext* context) {
    static NSCache<NSString*, NSNumber*>* cache;
    static BHTimelineFilterContext* cachedContext;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 4000;
    });

    if (![context isEqualToContext:cachedContext]) {
        [cache removeAllObjects];
        cachedContext = context;
    }

    return cache;
}

static BOOL MemoizedShouldHideTimelineItem(id item, NSCache<NSString*, NSNumber*>* cache,
                                           BHTimelineFilterContext* context) {
    NSString* entryID = ItemEntryID(unwrapDataViewItem(item));
    if (!entryID) {
        return ShouldHideTimelineItem(item, context);
    }

    NSNumber* cached = [cache objectForKey:entryID];
    if (cached) {
        return cached.boolValue;
    }

    BOOL hide = ShouldHideTimelineItem(item, context);
    [cache setObject:@(hide) forKey:entryID];
    return hide;
}

static long long ConversationRootUserID(NSArray* sections) {
    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }

        for (id item in (NSArray*)section) {
            id viewModel = unwrapDataViewItem(item);
            if (ItemIsConversationThreadReply(viewModel)) {
                continue;
            }

            long long userID = ItemRepresentedFromUserID(viewModel);
            if (userID != 0) {
                return userID;
            }
        }
    }

    return 0;
}

static NSSet<NSNumber*>* ConversationAuthorRepliedToUserIDs(NSArray* sections,
                                                            long long rootUserID) {
    NSMutableSet<NSNumber*>* repliedToUserIDs = [NSMutableSet set];
    if (rootUserID == 0) {
        return repliedToUserIDs;
    }

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }

        for (id item in (NSArray*)section) {
            id viewModel = unwrapDataViewItem(item);
            if (!ItemIsConversationThreadReply(viewModel)) {
                continue;
            }

            if (ItemRepresentedFromUserID(viewModel) != rootUserID) {
                continue;
            }

            long long repliedToUserID = ItemInReplyToUserID(viewModel);
            if (repliedToUserID != 0) {
                [repliedToUserIDs addObject:@(repliedToUserID)];
            }
        }
    }

    return repliedToUserIDs;
}

@implementation BHTimelineFilterContext

+ (instancetype)contextForDataViewController:(TFNItemsDataViewController*)dataViewController {
    BHTimelineFilterContext* context = [self new];

    context.inConversation =
        IsInHierarchyOfClass(dataViewController, @"T1ConversationContainerViewController");
    context.inProfile = IsInHierarchyOfClass(dataViewController, @"T1ProfileViewController");
    context.openedFromProfile = IsInProfileOriginConversation(dataViewController);
    context.inSearch = IsInHierarchyOfClass(dataViewController, @"TTSSearchContainerViewControllerV2");
    context.inEditHistory = IsInEditHistory(dataViewController);

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

    return context;
}

- (BOOL)shouldFilter {
    return self.hideWhoToFollow || self.hidePrompts || self.hideVerified ||
           self.hideQuoteTweets || self.hideRetweets || self.hideBlockedRetweets || self.inConversation;
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
           (self.authorRepliedToUserIDs == other.authorRepliedToUserIDs ||
            [self.authorRepliedToUserIDs isEqualToSet:other.authorRepliedToUserIDs]);
}

@end

static NSArray* FilteredTimelineSections(TFNItemsDataViewController* dataViewController,
                                         NSArray* sections) {
    BHTimelineFilterContext* context =
        [BHTimelineFilterContext contextForDataViewController:dataViewController];
    if (!context.shouldFilter) {
        return sections;
    }

    [context resolveConversationLookupsInSections:sections];
    NSCache<NSString*, NSNumber*>* verdicts = TimelineVerdictCacheForContext(context);

    // Modules can share a section with unrelated items, so filtering is per item;
    // a purely filtered section (like the Discover More one) empties and is dropped.
    BOOL modified = NO;
    NSMutableArray* filteredSections = [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < items.count; i++) {
            if (MemoizedShouldHideTimelineItem(items[i], verdicts, context)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        modified = YES;
        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? [filteredSections copy] : sections;
}

// MARK: - Videos for you module

// The server sends the carousel as one timeline entry, but the app expands it
// into separate header/content/footer view models. Drop the entry from the
// GraphQL response so the whole module never reaches that expansion.
static BOOL IsGraphQLResponse(NSURL* url) {
    return [url.path.pathComponents containsObject:@"graphql"];
}

static id RemoveVideoCarouselEntries(id node, BOOL* removed) {
    if ([node isKindOfClass:[NSArray class]]) {
        NSMutableArray* kept = [NSMutableArray array];
        for (id value in (NSArray*)node) {
            id entryID = [value isKindOfClass:[NSDictionary class]] ? value[@"entry_id"] : nil;
            if ([entryID isKindOfClass:[NSString class]] &&
                [entryID hasPrefix:@"video-carousel-"]) {
                *removed = YES;
                continue;
            }

            [kept addObject:RemoveVideoCarouselEntries(value, removed)];
        }
        return kept;
    }

    if ([node isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary* copy = [node mutableCopy];
        for (NSString* key in node) {
            copy[key] = RemoveVideoCarouselEntries(node[key], removed);
        }
        return copy;
    }

    return node;
}

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
    %orig(FilteredTimelineSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredTimelineSections(self, sections), identifiers, animation, completion);
}

%end
