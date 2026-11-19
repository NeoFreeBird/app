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
    UINavigationController* nav = home.navigationController;
    if (!home.viewIfLoaded.window || !nav) {
        return NO;
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

    [self.home.navigationController pushViewController:[BHTManager BHTSettingsWithAccount:account]
                                              animated:YES];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer {
    return [self homeIsVisible];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)other {
    return YES;
}

@end