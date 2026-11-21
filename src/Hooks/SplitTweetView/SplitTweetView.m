#import "SplitTweetView.h"

BOOL BHTSplitTweetViewEnabled(void) {
    return [BHTSettings boolForKey:@"ipad_split_view"];
}

BHTSplitTweetState* BHTTweetState(id object) {
    return object ? objc_getAssociatedObject(object, &BHTSplitTweetStateKey) : nil;
}

BHTSplitTweetState* BHTTweetStateForController(UIViewController* controller) {
    while (controller) {
        BHTSplitTweetState* state = BHTTweetState(controller);
        if (state) {
            return state;
        }
        controller = controller.parentViewController;
    }
    return nil;
}

BOOL BHTIsConversationController(UIViewController* controller) {
    Class conversationClass = NSClassFromString(@"T1ConversationContainerViewController");
    Class linkClass = NSClassFromString(@"T1XLinkViewController");
    // XLinks is the Swift route
    return (conversationClass && [controller isKindOfClass:conversationClass]) ||
           (linkClass && [controller isKindOfClass:linkClass]);
}

BOOL BHTRouteTweetToDetail(UINavigationController* primary, UIViewController* controller) {
    if (!BHTSplitTweetViewEnabled() || !BHTIsConversationController(controller)) {
        return NO;
    }
    BHTSplitTweetState* state = BHTTweetStateForController(primary);
    if (!state || primary == state.detail) {
        return NO;
    }
    return [state showConversation:controller fromPrimary:primary];
}

BOOL BHTRouteAppendedTweet(UINavigationController* primary, NSArray<UIViewController*>* controllers) {
    NSArray<UIViewController*>* existing = primary.viewControllers;
    if (!existing.count || controllers.count != existing.count + 1) {
        return NO;
    }
    for (NSUInteger index = 0; index < existing.count; index++) {
        if (existing[index] != controllers[index]) {
            return NO;
        }
    }
    return BHTRouteTweetToDetail(primary, controllers.lastObject);
}

BHTSplitTweetHostController* BHTMakeTweetColumnHost(UIViewController* content) {
    Class factory = NSClassFromString(@"NavigationControllerFactoryTFNFallback");
    if (!BHTSplitTweetViewEnabled() || !content || content.parentViewController ||
        [content isKindOfClass:BHTSplitTweetHostController.class] ||
        ![factory respondsToSelector:@selector(makeWithRootViewController:)]) {
        return nil;
    }

    UIViewController* empty = [UIViewController new];
    UINavigationController* detail = [factory makeWithRootViewController:empty];
    if (![detail isKindOfClass:UINavigationController.class]) {
        return nil;
    }
    BHTSplitTweetHostController* host = [[BHTSplitTweetHostController alloc] initWithContent:content detail:detail];
    BHTSplitTweetState* state = [BHTSplitTweetState new];
    state.glassHost = host;
    state.detail = detail;
    state.emptyController = empty;
    objc_setAssociatedObject(host, &BHTSplitTweetStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(detail, &BHTSplitTweetStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return host;
}

void BHTAttachTweetColumn(T1AppSplitViewController* split, BHTSplitTweetHostController* host) {
    if (!split) {
        return;
    }
    BHTSplitTweetState* state = BHTTweetState(host);
    state.split = split;
    objc_setAssociatedObject(split, &BHTSplitTweetStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

UIView* BHTTweetColumnAppView(BHTSplitTweetHostController* host) {
    id delegate = BHTTweetState(host).split.delegate;
    if (![delegate isKindOfClass:UIViewController.class]) return nil;
    for (UIViewController* parent = host.parentViewController; parent; parent = parent.parentViewController) {
        if (parent == delegate) return parent.viewIfLoaded;
    }
    return nil;
}

void BHTLayoutTweetColumnChrome(BHTSplitTweetHostController* host) {
    [host.content.viewIfLoaded layoutIfNeeded];
    UIView* appView = BHTTweetColumnAppView(host);
    [appView setNeedsLayout];
    [appView layoutIfNeeded];
    [host.content.viewIfLoaded layoutIfNeeded];
}
