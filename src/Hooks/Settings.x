//
//  Settings.x
//  NeoFreeBird
//

#import "Headers/XHeaders.h"
#import "HookHelpers.h"

// MARK: - NeoFreeBird settings entry

static const void* SettingsEntryKey = &SettingsEntryKey;
static const void* SettingsRootKey = &SettingsRootKey;

static BOOL isSettingsClass(UIViewController* viewController) {
    return [viewController isKindOfClass:objc_getClass("T1GenericSettingsViewController")] ||
           [viewController isKindOfClass:objc_getClass("T1SettingsViewController")];
}

// The generic controller backs the root and every sub-page alike, so the root is
// the first settings-class controller in the navigation stack.
static BOOL settingsVCIsRoot(TFNItemsDataViewController* settingsVC) {
    for (UIViewController* viewController in settingsVC.navigationController.viewControllers) {
        if (viewController == settingsVC) {
            return YES;
        }

        if (isSettingsClass(viewController)) {
            return NO;
        }
    }

    return NO;
}

static BOOL sectionsContainNeoFreeBirdEntry(NSArray* sections) {
    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }

        for (id entry in (NSArray*)section) {
            if (objc_getAssociatedObject(entry, SettingsEntryKey)) {
                return YES;
            }
        }
    }

    return NO;
}

static TFNSettingsNavigationItem* makeNeoFreeBirdSettingsItem(
    TFNItemsDataViewController* settingsVC) {
    UIColor* iconColor;
    if (@available(iOS 12.0, *)) {
        if (settingsVC.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            iconColor = [UIColor systemGray2Color];
        } else {
            iconColor = [UIColor secondaryLabelColor];
        }
    } else {
        iconColor = [UIColor secondaryLabelColor];
    }

    UIImage* twitterIcon = [UIImage tfn_vectorImageNamed:@"twitter"
                                                fitsSize:CGSizeMake(20, 20)
                                               fillColor:iconColor];

    TFNTwitterAccount* account = [(T1GenericSettingsViewController*)settingsVC account];
    TFNSettingsNavigationItem* bhtwitter = [[objc_getClass("TFNSettingsNavigationItem") alloc]
            initWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"]
                   detail:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_DETAIL"]
                 iconName:nil
        controllerFactory:^UIViewController* {
            return [BHTManager BHTSettingsWithAccount:account];
        }];

    if (twitterIcon) {
        [bhtwitter setValue:twitterIcon forKey:@"icon"];
    }

    objc_setAssociatedObject(bhtwitter, SettingsEntryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    return bhtwitter;
}

static NSArray* sectionsByInsertingEntry(TFNItemsDataViewController* settingsVC,
                                         NSArray* sections) {
    NSMutableArray* newSections = [sections mutableCopy] ?: [NSMutableArray array];
    [newSections insertObject:@[makeNeoFreeBirdSettingsItem(settingsVC)] atIndex:0];
    return newSections;
}

// Async settings fetches rebuild the sections and discard one-shot inserts, and
// root-ness is unknowable during the first build (not yet on the nav stack). So
// tag the root in viewWillAppear, insert once to repair the first build, and let
// the rebuild transform below re-add the entry on every later snapshot.
static void insertNeoFreeBirdSettingsIfRoot(TFNItemsDataViewController* settingsVC) {
    if (!settingsVCIsRoot(settingsVC)) {
        return;
    }

    objc_setAssociatedObject(settingsVC, SettingsRootKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (sectionsContainNeoFreeBirdEntry(settingsVC.sections)) {
        return;
    }

    settingsVC.sections = sectionsByInsertingEntry(settingsVC, settingsVC.sections);
}

static NSArray* sectionsWithNeoFreeBirdEntry(TFNItemsDataViewController* settingsVC,
                                             NSArray* sections) {
    if (!isSettingsClass(settingsVC)) {
        return sections;
    }

    if (![objc_getAssociatedObject(settingsVC, SettingsRootKey) boolValue]) {
        return sections;
    }

    if (sectionsContainNeoFreeBirdEntry(sections)) {
        return sections;
    }

    return sectionsByInsertingEntry(settingsVC, sections);
}

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

@interface NFBSettingsGesture : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController* home;
@end

@implementation NFBSettingsGesture

// X 12.45.1 (Liquid Glass) does not reliably give the home timeline a navigation
// controller any more, so visibility is judged by the home view itself and the
// stack check only applies when a navigation controller is actually there.
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
        // Liquid Glass home: there is no stack to consult, so the home view
        // being on screen and unhidden is the whole test.
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

    // The press can land on the sheet we just opened, so don't stack another.
    if ([presenter isKindOfClass:[ModernSettingsViewController class]]) {
        return;
    }

    // No stack to push onto: present the settings wrapped in a navigation
    // controller so its own pages can still push and the sheet can be swiped away.
    UINavigationController* modal =
        [[UINavigationController alloc] initWithRootViewController:settings];
    [presenter presentViewController:modal animated:YES completion:nil];
}

// The gesture lives on the window, so only the top-centre logo band belongs to
// it; every other long press has to keep going to the app.
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

static const void* SettingsGestureKey = &SettingsGestureKey;

// Code lifted from nyaathea's Twitter tweak (now abandoned)
// Attached to the home window rather than to its navigation bar: on X 12.45.1
// the bar answers hitTest: with nil over the logo, so a recognizer on the bar
// never saw the press at all.
void attachNeoFreeBirdSettingsGesture(UIViewController* home) {
    UIView* host = home.view.window;
    if (!host) {
        host = [UIApplication sharedApplication].keyWindow;
    }
    if (!host) {
        return;
    }

    NFBSettingsGesture* target = objc_getAssociatedObject(host, SettingsGestureKey);
    if (target) {
        target.home = home;
        return;
    }

    target = [NFBSettingsGesture new];
    target.home = home;

    UILongPressGestureRecognizer* press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:target
                                                      action:@selector(handleLongPress:)];
    press.cancelsTouchesInView = NO;
    press.delegate = target;
    [host addGestureRecognizer:press];

    objc_setAssociatedObject(host, SettingsGestureKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
