#import "Settings.h"

// MARK: - NeoFreeBird settings entry

%hook T1GenericSettingsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    insertNeoFreeBirdSettingsIfRoot(self);
}
%end

%hook T1SettingsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    insertNeoFreeBirdSettingsIfRoot(self);
}
%end

// Every sections rebuild runs through this transform right before setSections:,
// so hooking it on the base class covers both settings roots.
%hook TFNItemsDataViewController
- (NSArray*)updatedSections:(NSArray*)sections forStyle:(NSInteger)style {
    NSArray* updatedSections = %orig;
    return sectionsWithNeoFreeBirdEntry(self, updatedSections);
}
%end

// MARK: - NeoFreeBird settings gesture

@implementation NFBSettingsGesture

- (BOOL)homeIsVisible {
    UIViewController* home = self.home;
    if (!home) {
        return NO;
    }

    UIView* homeView = home.viewIfLoaded;
    if (!homeView.window || homeView.hidden) {
        return NO;
    }

    UINavigationController* nav = home.navigationController;
    if (!nav) {
        return YES;
    }

    UIViewController* top = nav.topViewController;
    for (UIViewController* vc = home; vc; vc = vc.parentViewController) {
        if (vc == top) {
            return YES;
        }
    }

    return NO;
}

- (void)handleLongPress:(UILongPressGestureRecognizer*)press {
    if (press.state != UIGestureRecognizerStateBegan || ![self homeIsVisible]) {
        return;
    }

    UIImpactFeedbackGenerator* haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    id account = nil;
    Class hostClass = objc_getClass("T1HostViewController");
    if ([hostClass respondsToSelector:@selector(sharedHostViewController)]) {
        id host = [hostClass sharedHostViewController];
        if ([host respondsToSelector:@selector(currentAccount)]) {
            account = [host currentAccount];
        }
    }

    UIViewController* settings = [BHTManager BHTSettingsWithAccount:account];
    if (!settings) {
        return;
    }

    UINavigationController* nav = self.home.navigationController;
    if (nav) {
        [nav pushViewController:settings animated:YES];
        return;
    }

    UIViewController* presenter = topMostController();
    if (!presenter) {
        return;
    }

    if ([presenter isKindOfClass:[ModernSettingsViewController class]]) {
        return;
    }

    UINavigationController* modal =
        [[UINavigationController alloc] initWithRootViewController:settings];
    [presenter presentViewController:modal animated:YES completion:nil];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer {
    if (![self homeIsVisible]) {
        return NO;
    }

    UIView* view = gestureRecognizer.view;
    if (!view) {
        return NO;
    }

    CGRect bounds = view.bounds;
    if (CGRectGetWidth(bounds) <= 0 || CGRectGetHeight(bounds) <= 0) {
        return NO;
    }

    CGPoint point = [gestureRecognizer locationInView:view];
    CGFloat x = (point.x - CGRectGetMinX(bounds)) / CGRectGetWidth(bounds);
    CGFloat y = (point.y - CGRectGetMinY(bounds)) / CGRectGetHeight(bounds);

    return y >= 0 && y <= 0.13 && x >= 0.15 && x <= 0.85;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)other {
    return YES;
}

@end
