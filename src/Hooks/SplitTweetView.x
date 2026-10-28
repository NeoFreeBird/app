//
//  SplitTweetView.x
//  Made by orionblur
//
// Before 12.38, the old app style uses X's extended-content column (where the search column is).
// Liquid Glass, and both styles on 12.38+, use our two-pane content container instead.
// Both styles reuse the conversation controllers and navigation styles made by X, so this file just
// stitches the two-pane layout into the app's split view and tab navigation.
// This only works on iPads, but I think this can work on the iPhone Duo when unfolded.

#import "HookHelpers.h"
#import "Headers/T1Headers.h"
#import "Headers/XHeaders.h"
#import "Headers/TFNHeaders.h"

@protocol BHTSplitAppNavigation <NSObject>
- (id)appNavigation;
- (UIViewController*)currentPanelNavigationController;
@end

@interface T1TabbedAppNavigationViewController (BHTSplitTweet)
@property (nonatomic, readonly) UINavigationController* currentTabNavigationController;
@end

static char BHTSplitTweetStateKey;
static const CGFloat BHTSplitTweetPrimaryWidthFraction = 0.55;

@interface BHTSplitTweetHostController : UIViewController
@property (nonatomic, strong) UIViewController* content;
@property (nonatomic, strong) UINavigationController* detail;
@property (nonatomic, strong) UIView* divider;
@property (nonatomic) BOOL detailVisible;
@property (nonatomic) BOOL appeared;
@property (nonatomic, strong) UIViewPropertyAnimator* columnAnimator;
- (instancetype)initWithContent:(UIViewController*)content detail:(UINavigationController*)detail;
- (BOOL)hasRoomForDetail;
- (void)finishColumnAnimation;
- (void)setDetailVisible:(BOOL)visible animated:(BOOL)animated completion:(void (^)(void))completion;
@end

@interface BHTSplitTweetState : NSObject
@property (nonatomic, weak) T1AppSplitViewController* split;
@property (nonatomic, weak) BHTSplitTweetHostController* glassHost;
@property (nonatomic, weak) UINavigationController* detail;
@property (nonatomic, weak) UINavigationController* primary;
@property (nonatomic, weak) UIViewController* primaryScreen;
@property (nonatomic, weak) UIViewController* conversation;
@property (nonatomic, strong) UIViewController* emptyController;
@property (nonatomic, copy) NSArray<UIBarButtonItem*>* originalLeftItems;
@property (nonatomic, strong) UIBarButtonItem* closeItem;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL collapsed;
@property (nonatomic) BOOL updating;
@property (nonatomic) BOOL updateScheduled;
@property (nonatomic) BOOL waitingForTransition;
@property (nonatomic) BOOL nativeColumnTransitioning;
- (BOOL)showConversation:(UIViewController*)controller
            fromPrimary:(UINavigationController*)primary;
- (void)scheduleUpdate;
- (void)discardHiddenDetail;
@end

static BHTSplitTweetState* BHTTweetState(id object) {
    return object ? objc_getAssociatedObject(object, &BHTSplitTweetStateKey) : nil;
}

static BHTSplitTweetState* BHTTweetStateForController(UIViewController* controller) {
    while (controller) {
        BHTSplitTweetState* state = BHTTweetState(controller);
        if (state) {
            return state;
        }
        controller = controller.parentViewController;
    }
    return nil;
}

static BOOL BHTIsConversationController(UIViewController* controller) {
    Class conversationClass = NSClassFromString(@"T1ConversationContainerViewController");
    Class linkClass = NSClassFromString(@"T1XLinkViewController");
    // XLinks is the tweet + linked-article container used by the modern router.
    // Its Swift initializer can bypass an Objective-C initializer hook entirely.
    return (conversationClass && [controller isKindOfClass:conversationClass]) ||
        (linkClass && [controller isKindOfClass:linkClass]);
}

@implementation BHTSplitTweetHostController

- (instancetype)initWithContent:(UIViewController*)content detail:(UINavigationController*)detail {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _content = content;
        _detail = detail;
    }
    return self;
}

- (BOOL)hasRoomForDetail {
    // Measure the actual window content, including Stage Manager/Split View.
    // Should only be true on a landscape iPad (and technically an unfolded Duo)
    return self.isViewLoaded && self.view.window && CGRectGetWidth(self.view.bounds) >= 800.0;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self addChildViewController:self.content];
    self.content.view.frame = self.view.bounds;
    [self.view addSubview:self.content.view];
    [self.content didMoveToParentViewController:self];
    self.divider = [UIView new];
    self.divider.backgroundColor = UIColor.separatorColor;
    self.divider.hidden = YES;
    [self.view addSubview:self.divider];
    self.view.clipsToBounds = YES;
}

- (void)setDetailVisible:(BOOL)visible {
    [self setDetailVisible:visible animated:NO completion:nil];
}

- (void)finishColumnAnimation {
    UIViewPropertyAnimator* animator = self.columnAnimator;
    if (animator.state == UIViewAnimatingStateActive) {
        [animator stopAnimation:NO];
        [animator finishAnimationAtPosition:UIViewAnimatingPositionEnd];
    }
}

- (void)setDetailVisible:(BOOL)visible animated:(BOOL)animated completion:(void (^)(void))completion {
    [self finishColumnAnimation];
    if (_detailVisible == visible) {
        if (completion) completion();
        return;
    }
    [self loadViewIfNeeded];
    [self.view layoutIfNeeded];
    BOOL animate = animated && self.appeared && self.view.window &&
        !UIAccessibilityIsReduceMotionEnabled() && UIView.areAnimationsEnabled;
    BOOL forwardAppearance = self.appeared;
    if (visible) {
        [self addChildViewController:self.detail];
        if (forwardAppearance) {
            [self.detail beginAppearanceTransition:YES animated:animate];
        }
        CGFloat width = CGRectGetWidth(self.view.bounds);
        CGFloat divider = 1.0 / MAX(self.view.window.screen.scale, 1.0);
        CGFloat detailWidth = width - divider - floor((width - divider) * BHTSplitTweetPrimaryWidthFraction);
        self.detail.view.frame = CGRectMake(width, 0, detailWidth, CGRectGetHeight(self.view.bounds));
        self.divider.frame = CGRectMake(width, 0, divider, CGRectGetHeight(self.view.bounds));
        [self.view addSubview:self.detail.view];
        [self.detail didMoveToParentViewController:self];
    } else {
        [self.detail willMoveToParentViewController:nil];
        if (forwardAppearance) {
            [self.detail beginAppearanceTransition:NO animated:animate];
        }
    }
    _detailVisible = visible;
    self.divider.hidden = NO;
    // Keep the actual detail controller attached until the closing animation
    // ends. Emptying its stack early would animate a blank pane.
    __weak BHTSplitTweetHostController* weakSelf = self;
    void (^layout)(void) = ^{
        BHTSplitTweetHostController* host = weakSelf;
        [host.view setNeedsLayout];
        [host.view layoutIfNeeded];
    };
    void (^finish)(UIViewAnimatingPosition) = ^(UIViewAnimatingPosition position) {
        BHTSplitTweetHostController* host = weakSelf;
        if (!host) return;
        host.columnAnimator = nil;
        if (!visible) {
            [host.detail.view removeFromSuperview];
            [host.detail removeFromParentViewController];
        }
        host.divider.hidden = !visible;
        if (forwardAppearance) [host.detail endAppearanceTransition];
        if (completion) completion();
        [BHTTweetState(host) scheduleUpdate];
    };
    if (animate) {
        // Match T1AppSplitViewController's spring branch (damping ratio 0.75).
        UISpringTimingParameters* timing = [[UISpringTimingParameters alloc] initWithDampingRatio:0.75];
        UIViewPropertyAnimator* animator = [[UIViewPropertyAnimator alloc]
            initWithDuration:CATransaction.animationDuration timingParameters:timing];
        self.columnAnimator = animator;
        [animator addAnimations:layout];
        [animator addCompletion:finish];
        [animator startAnimation];
    } else {
        layout();
        finish(UIViewAnimatingPositionEnd);
    }
}

- (CGSize)sizeForChildContentContainer:(id<UIContentContainer>)container
             withParentContainerSize:(CGSize)parentSize {
    if (self.detailVisible && (container == self.content || container == self.detail)) {
        CGFloat dividerWidth = 1.0 / MAX(self.view.window.screen.scale, 1.0);
        CGFloat availableWidth = MAX(0.0, parentSize.width - dividerWidth);
        CGFloat leftWidth = floor(availableWidth * BHTSplitTweetPrimaryWidthFraction);
        CGFloat width = container == self.content ? leftWidth : availableWidth - leftWidth;
        return CGSizeMake(width, parentSize.height);
    }
    return parentSize;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat dividerWidth = 1.0 / MAX(self.view.window.screen.scale, 1.0);
    CGSize contentSize = [self sizeForChildContentContainer:self.content
                                  withParentContainerSize:bounds.size];
    CGFloat leftWidth = contentSize.width;
    self.content.view.frame = CGRectMake(0, 0, leftWidth, bounds.size.height);
    if (self.detailVisible) {
        self.divider.frame = CGRectMake(leftWidth, 0, dividerWidth, bounds.size.height);
        self.detail.view.frame = CGRectMake(leftWidth + dividerWidth, 0,
                                           bounds.size.width - leftWidth - dividerWidth, bounds.size.height);
    } else if (self.detail.parentViewController == self) {
        // Closing: slide the attached pane past the trailing edge.
        CGRect frame = self.detail.view.frame;
        frame.origin.x = bounds.size.width;
        frame.size.height = bounds.size.height;
        self.detail.view.frame = frame;
        self.divider.frame = CGRectMake(bounds.size.width, 0, dividerWidth, bounds.size.height);
    }
    [BHTTweetState(self) scheduleUpdate];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.appeared = YES;
    [BHTTweetState(self) scheduleUpdate];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.appeared = NO;
    [self finishColumnAnimation];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self finishColumnAnimation];
    [super viewWillDisappear:animated];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [self finishColumnAnimation];
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (UIViewController*)childViewControllerForStatusBarStyle {
    return self.content;
}

- (UIViewController*)childViewControllerForStatusBarHidden {
    return self.content;
}

@end

@implementation BHTSplitTweetState

- (UINavigationController*)currentPrimary {
    id delegate = self.split.delegate;
    id primary = nil;
    if ([delegate respondsToSelector:@selector(currentTabNavigationController)]) {
        primary = [delegate currentTabNavigationController];
    } else if ([delegate respondsToSelector:@selector(appNavigation)]) {
        id<BHTSplitAppNavigation> router = [(id<BHTSplitAppNavigation>)delegate appNavigation];
        if ([router respondsToSelector:@selector(currentPanelNavigationController)]) {
            primary = [router currentPanelNavigationController];
        }
    }
    return [primary isKindOfClass:UINavigationController.class] ? primary : nil;
}

- (BOOL)hasRoomForDetail {
    if (self.glassHost) {
        return [self.glassHost hasRoomForDetail];
    }
    T1AppSplitViewController* split = self.split;
    if (!split.isViewLoaded || !split.view.window) {
        return NO;
    }
    // These are the extended-content modes checked by X's own
    // -private_updateExtendedContentAvailable. Let X calculate widths/insets.
    NSInteger mode = [split private_splitModeForSize:split.view.bounds.size
                            displayExtendedContent:YES
                                    displaySideBar:split.displaySideBar];
    return mode == 4 || mode == 5 || mode == 6;
}

- (void)setDetailVisible:(BOOL)visible {
    [self setDetailVisible:visible animated:NO];
}

- (void)setDetailVisible:(BOOL)visible animated:(BOOL)animated {
    if (self.glassHost) {
        [self.glassHost setDetailVisible:visible animated:animated completion:nil];
    } else {
        [self.split setDisplayExtendedContent:visible animated:animated && !UIAccessibilityIsReduceMotionEnabled()];
    }
}

- (void)restoreCloseItem {
    if (self.closeItem &&
        [self.conversation.navigationItem.leftBarButtonItems containsObject:self.closeItem]) {
        self.conversation.navigationItem.leftBarButtonItems = self.originalLeftItems;
    }
    self.originalLeftItems = nil;
    self.closeItem = nil;
}

- (void)installCloseItem {
    // Do this after installing the stack, so the conversation's viewDidLoad
    // can finish setting up its own navigation item first.
    self.originalLeftItems = self.conversation.navigationItem.leftBarButtonItems;
    self.closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                               target:self
                                                               action:@selector(closeDetail:)];
    NSMutableArray* items = [NSMutableArray arrayWithObject:self.closeItem];
    [items addObjectsFromArray:self.originalLeftItems ?: @[]];
    self.conversation.navigationItem.leftBarButtonItems = items;
}

- (void)clearDetail {
    [self clearDetailAnimated:NO];
}

- (void)discardHiddenDetail {
    if (!self.active) {
        [self.detail setViewControllers:@[self.emptyController] animated:NO];
    }
}

- (void)clearDetailAnimated:(BOOL)animated {
    [self.glassHost finishColumnAnimation];
    [self restoreCloseItem];
    self.active = NO;
    self.collapsed = NO;
    self.conversation = nil;
    self.primaryScreen = nil;
    self.primary = nil;
    if (self.glassHost) {
        __weak BHTSplitTweetState* weakSelf = self;
        [self.glassHost setDetailVisible:NO animated:animated completion:^{
            [weakSelf discardHiddenDetail];
        }];
    } else {
        [self setDetailVisible:NO animated:animated];
        // The native split's completion hook discards the stack after it slides
        // out. Nonanimated cleanup can finish immediately.
        if (!animated || UIAccessibilityIsReduceMotionEnabled()) [self discardHiddenDetail];
    }
}

- (void)closeDetail:(id)sender {
    [self.detail.view endEditing:YES];
    [self clearDetailAnimated:YES];
}

- (BOOL)showConversation:(UIViewController*)controller
            fromPrimary:(UINavigationController*)primary {
    [self.glassHost finishColumnAnimation];
    if (self.updating || self.collapsed || !self.detail ||
        primary != [self currentPrimary] || ![self hasRoomForDetail] ||
        primary.presentedViewController || self.detail.presentedViewController ||
        primary.transitionCoordinator || self.detail.transitionCoordinator ||
        controller.parentViewController || !primary.topViewController ||
        BHTIsConversationController(primary.topViewController)) {
        return NO;
    }

    self.updating = YES;
    [self restoreCloseItem];
    self.primary = primary;
    self.primaryScreen = primary.topViewController;
    self.conversation = controller;
    self.active = YES;
    // X has already built this controller, including the account, tweet model,
    // reply sorting and navigation metadata. Only its destination changes.
    [self.detail setViewControllers:@[controller] animated:NO];
    [self setDetailVisible:YES animated:YES];
    [self installCloseItem];
    self.updating = NO;
    return YES;
}

- (void)updateLayout {
    if (self.updating || !self.active || !self.split.viewIfLoaded.window ||
        self.glassHost.columnAnimator || self.nativeColumnTransitioning) {
        return;
    }
    UINavigationController* primary = self.primary;
    UINavigationController* selected = [self currentPrimary];
    UIViewController* conversation = self.conversation;
    if (!primary || !conversation || !selected) {
        [self clearDetail];
        return;
    }

    // Moving controllers during a push/pop or while a sheet is presented can
    // invalidate UIKit's presentation hierarchy. Retry after the transition.
    if (primary.presentedViewController || selected.presentedViewController ||
        self.detail.presentedViewController || self.split.presentedViewController) {
        return;
    }
    id<UIViewControllerTransitionCoordinator> transition =
        selected.transitionCoordinator ?: primary.transitionCoordinator ?: self.detail.transitionCoordinator;
    if (transition) {
        if (!self.waitingForTransition) {
            self.waitingForTransition = YES;
            __weak BHTSplitTweetState* weakSelf = self;
            BOOL registered = [transition animateAlongsideTransition:nil
                                        completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                                            weakSelf.waitingForTransition = NO;
                                            [weakSelf scheduleUpdate];
                                        }];
            if (!registered) {
                // A coordinator can stop accepting callbacks before it leaves
                // the hierarchy. Retry without spinning the main run loop.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    weakSelf.waitingForTransition = NO;
                    [weakSelf scheduleUpdate];
                });
            }
        }
        return;
    }

    BOOL hasRoom = [self hasRoomForDetail];
    if (selected != primary) {
        // Persistence requires the same account-scoped split owner. Never move
        // a collapsed conversation out of an inactive tab, or adopt a modal /
        // detached tab. UIKit exceptions cannot prove a drawing hierarchy safe.
        if (self.collapsed || !hasRoom || BHTTweetStateForController(selected) != self ||
            !selected.topViewController || BHTIsConversationController(selected.topViewController) ||
            selected.viewIfLoaded.window != self.split.viewIfLoaded.window ||
            primary.topViewController != self.primaryScreen ||
            self.detail.viewControllers.firstObject != conversation ||
            conversation.parentViewController != self.detail) {
            [self clearDetail];
            return;
        }
        self.primary = primary = selected;
        self.primaryScreen = selected.topViewController;
    }

    if (!self.collapsed && ![self hasValidDetailHierarchy]) {
        [self clearDetail];
        return;
    }
    NSArray<UIViewController*>* primaryStack = primary.viewControllers;
    if (self.collapsed) {
        NSUInteger index = [primaryStack indexOfObjectIdenticalTo:conversation];
        if (index == NSNotFound || index == 0 || primaryStack[index - 1] != self.primaryScreen) {
            // Back was pressed, or X replaced the tab's stack while compact.
            [self clearDetail];
            return;
        }
        if (hasRoom) {
            self.updating = YES;
            NSArray* detailStack = [primaryStack subarrayWithRange:NSMakeRange(index, primaryStack.count - index)];
            // A controller must leave one navigation stack before joining the other.
            [primary setViewControllers:[primaryStack subarrayWithRange:NSMakeRange(0, index)] animated:NO];
            [self.detail setViewControllers:detailStack animated:NO];
            self.collapsed = NO;
            [self setDetailVisible:YES];
            [self installCloseItem];
            self.updating = NO;
        }
    } else if (primary.topViewController != self.primaryScreen) {
        // A new navigation within the current tab still invalidates its anchor.
        [self clearDetailAnimated:YES];
    } else if (!hasRoom) {
        self.updating = YES;
        NSArray* detailStack = self.detail.viewControllers;
        [self restoreCloseItem];
        [self.detail setViewControllers:@[self.emptyController] animated:NO];
        self.collapsed = YES;
        [primary setViewControllers:[primaryStack arrayByAddingObjectsFromArray:detailStack] animated:NO];
        [self setDetailVisible:NO];
        self.updating = NO;
    }
}

- (BOOL)hasValidDetailHierarchy {
    if (self.detail.viewControllers.firstObject != self.conversation ||
        self.conversation.parentViewController != self.detail) return NO;
    BHTSplitTweetHostController* host = self.glassHost;
    if (!host) {
        return self.split.extendedContentViewController == self.detail &&
            BHTTweetStateForController(self.detail.parentViewController) == self &&
            self.detail.viewIfLoaded.window == self.split.viewIfLoaded.window;
    }
    if (!host.detailVisible || host.content.parentViewController != host ||
        self.detail.parentViewController != host ||
        host.content.viewIfLoaded.superview != host.view ||
        self.detail.viewIfLoaded.superview != host.view ||
        self.detail.viewIfLoaded.window != host.view.window) return NO;
    CGRect left = host.content.view.frame;
    CGRect right = self.detail.view.frame;
    CGFloat width = CGRectGetWidth(host.view.bounds);
    CGFloat height = CGRectGetHeight(host.view.bounds);
    CGFloat divider = 1.0 / MAX(host.view.window.screen.scale, 1.0);
    CGFloat expectedLeft = floor(MAX(0.0, width - divider) * BHTSplitTweetPrimaryWidthFraction);
    // Comparisons also reject NaN/infinite geometry. Check only after animation
    // and tab transitions settle, when frames represent the final layout.
    return width > 0 && height > 0 &&
        fabs(left.origin.x) < 1 && fabs(left.origin.y) < 1 &&
        fabs(left.size.width - expectedLeft) < 1 && fabs(left.size.height - height) < 1 &&
        fabs(right.origin.x - expectedLeft - divider) < 1 && fabs(right.origin.y) < 1 &&
        fabs(right.size.width - (width - expectedLeft - divider)) < 1 &&
        fabs(right.size.height - height) < 1;
}

- (void)scheduleUpdate {
    if (self.updateScheduled || self.updating || !self.active) {
        return;
    }
    self.updateScheduled = YES;
    __weak BHTSplitTweetState* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        BHTSplitTweetState* state = weakSelf;
        state.updateScheduled = NO;
        [state updateLayout];
    });
}

@end

static BOOL BHTRouteTweetToDetail(UINavigationController* primary, UIViewController* controller) {
    if (!BHTIsConversationController(controller)) {
        return NO;
    }
    BHTSplitTweetState* state = BHTTweetStateForController(primary);
    if (!state || primary == state.detail) {
        return NO;
    }
    return [state showConversation:controller fromPrimary:primary];
}

static BOOL BHTRouteAppendedTweet(UINavigationController* primary, NSArray<UIViewController*>* controllers) {
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

static BHTSplitTweetHostController* BHTMakeTweetColumnHost(UIViewController* content) {
    Class factory = NSClassFromString(@"NavigationControllerFactoryTFNFallback");
    if (!content || content.parentViewController ||
        [content isKindOfClass:BHTSplitTweetHostController.class] ||
        ![factory respondsToSelector:@selector(makeWithRootViewController:)]) {
        return nil;
    }

    UIViewController* empty = [UIViewController new];
    // XNAVNavigationController's standard UIKit initializers trap. X's own
    // factory supplies its pinned glass configuration and pop-gesture policy.
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

static void BHTAttachTweetColumn(T1AppSplitViewController* split, BHTSplitTweetHostController* host) {
    if (!split) {
        return;
    }
    BHTSplitTweetState* state = BHTTweetState(host);
    state.split = split;
    objc_setAssociatedObject(split, &BHTSplitTweetStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%group BHTIPadModernTweetColumn

%hook T1AppSplitViewController

- (id)initWithDashContentController:(id)dash
              tabBarViewController:(id)tabBar
    tabBottomSegmentViewController:(id)bottomSegment
             contentViewController:(UIViewController*)content
                           account:(id)account {
    // 12.38 removed extendedContentViewController: and the native auxiliary
    // column. Both navigation styles now enter through this initializer.
    BHTSplitTweetHostController* host = BHTMakeTweetColumnHost(content);
    if (!host) {
        return %orig;
    }
    T1AppSplitViewController* split = %orig(dash, tabBar, bottomSegment, host, account);
    BHTAttachTweetColumn(split, host);
    return split;
}

%end

%end

%group BHTIPadLegacyTweetColumn

%hook XTabbedAppNavigationSplitViewControllerFactory

+ (id)splitViewControllerWithDashContentController:(id)dash
                           contentViewController:(UIViewController*)content
                                         account:(id)account {
    BHTSplitTweetHostController* host = BHTMakeTweetColumnHost(content);
    if (!host) {
        return %orig;
    }
    T1AppSplitViewController* split = %orig(dash, host, account);
    BHTAttachTweetColumn(split, host);
    return split;
}

%end

%hook T1AppSplitViewController

- (id)initWithDashContentController:(id)dash
              tabBarViewController:(id)tabBar
    tabBottomSegmentViewController:(id)bottomSegment
             contentViewController:(id)content
     extendedContentViewController:(id)extended
                           account:(id)account {
    Class extendedClass = %c(T1ExtendedContentNavigationController);
    // The legacy tab bar identifies the native-column path. The redesign's
    // factory passes nil and already wraps its content in our host.
    if (!tabBar || !extendedClass ||
        ![self respondsToSelector:@selector(private_splitModeForSize:displayExtendedContent:displaySideBar:)] ||
        (extended && ![extended isKindOfClass:extendedClass])) {
        return %orig;
    }

    T1ExtendedContentNavigationController* detail = extended ?: [[extendedClass alloc] init];
    if (!detail) {
        return %orig;
    }
    BHTSplitTweetState* state = [BHTSplitTweetState new];
    state.detail = detail;
    state.emptyController = [UIViewController new];
    // Associate before initialization can trigger the legacy data-source observer.
    objc_setAssociatedObject(detail, &BHTSplitTweetStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    T1AppSplitViewController* split = %orig(dash, tabBar, bottomSegment, content, detail, account);
    if (!split) {
        objc_setAssociatedObject(detail, &BHTSplitTweetStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return nil;
    }
    state.split = split;
    objc_setAssociatedObject(split, &BHTSplitTweetStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [detail setViewControllers:@[state.emptyController] animated:NO];
    [split setDisplayExtendedContent:NO animated:NO];
    return split;
}

- (void)setDisplayExtendedContent:(BOOL)display animated:(BOOL)animated {
    BHTSplitTweetState* state = BHTTweetState(self);
    if (state.glassHost) {
        // Liquid Glass keeps X's single-content layout. The two panes live
        // inside that content, without changing the redesign/phone-stack gate.
        %orig(NO, animated);
        return;
    }
    // The legacy display setting controls the auxiliary pane. Our pane is
    // instead visible while it has a selected conversation and enough room.
    %orig(state ? (state.active && !state.collapsed) : display, animated);
}

- (void)private_updateForSplitModeWithSizeTransition:(BOOL)transition
                                    removeSubviews:(BOOL)removeSubviews
                                         prelayout:(BOOL)prelayout {
    BHTSplitTweetState* state = BHTTweetState(self);
    if (state && !state.glassHost && prelayout) state.nativeColumnTransitioning = YES;
    %orig;
    // Both native animation branches call this with removeSubviews:YES and
    // transition:NO at completion. Do not clear content in the animation block.
    if (state && !state.glassHost && removeSubviews && !prelayout) {
        state.nativeColumnTransitioning = NO;
        [state discardHiddenDetail];
        [state scheduleUpdate];
    }
}

%end

%end

%group BHTIPadTweetColumn

%hook T1AppSplitViewController

- (void)viewDidLayoutSubviews {
    %orig;
    [BHTTweetState(self) scheduleUpdate];
}

%end

%hook T1TabNavigationController

- (void)pushViewController:(UIViewController*)controller animated:(BOOL)animated {
    if (BHTRouteTweetToDetail(self, controller)) {
        return;
    }
    %orig;
    [BHTTweetStateForController(self) scheduleUpdate];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [BHTTweetStateForController(self) scheduleUpdate];
}

%end

%hook XNAVNavigationController

- (void)pushViewController:(UIViewController*)controller animated:(BOOL)animated {
    if (BHTRouteTweetToDetail(self, controller)) {
        return;
    }
    %orig;
    [BHTTweetStateForController(self) scheduleUpdate];
}

- (void)setViewControllers:(NSArray<UIViewController*>*)controllers animated:(BOOL)animated {
    if (BHTRouteAppendedTweet(self, controllers)) {
        return;
    }
    %orig;
    [BHTTweetStateForController(self) scheduleUpdate];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [BHTTweetStateForController(self) scheduleUpdate];
}

%end

%end

%group BHTIPadLegacyDetailNavigation

%hook T1ExtendedContentNavigationController

- (void)_t1_updateContentViewControllerAnimated:(BOOL)animated {
    BHTSplitTweetState* state = BHTTweetState(self);
    if (state) {
        [state scheduleUpdate];
        return;
    }
    %orig;
}

- (id)viewController:(UIViewController*)controller willPresentWithPresentationInfo:(id)info {
    // The original implementation re-presents the destination from the main
    // panel and returns nil. Keep replies/profiles in the detail stack instead.
    return BHTTweetState(self) ? controller : %orig;
}

- (BOOL)tfn_isResponderChainVetoed {
    return BHTTweetState(self) ? NO : %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [BHTTweetState(self) scheduleUpdate];
}

%end

%end

%ctor {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        %init(BHTIPadTweetColumn);
        Class splitClass = NSClassFromString(@"T1AppSplitViewController");
        if (class_getInstanceMethod(splitClass, @selector(initWithDashContentController:tabBarViewController:tabBottomSegmentViewController:contentViewController:account:))) {
            %init(BHTIPadModernTweetColumn);
        } else if (class_getInstanceMethod(splitClass, @selector(initWithDashContentController:tabBarViewController:tabBottomSegmentViewController:contentViewController:extendedContentViewController:account:))) {
            %init(BHTIPadLegacyTweetColumn);
            %init(BHTIPadLegacyDetailNavigation);
        }
    }
}
