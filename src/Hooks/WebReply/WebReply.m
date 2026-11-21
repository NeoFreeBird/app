#import "WebReply.h"

static void openStatusNatively(NSString* statusID) {
    if (statusID.length == 0) {
        return;
    }

    NSURL* url =
        [NSURL URLWithString:[NSString stringWithFormat:@"twitter://status?id=%@", statusID]];
    if (!url) {
        return;
    }

    id delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(openURL:options:)]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, @selector(openURL:options:), url, @{});
    }
}

TFNTwitterStatus* statusFromObject(id object) {
    if (!object) {
        return nil;
    }

    if ([object isKindOfClass:(Class)objc_getClass("TFNTwitterStatus")]) {
        return (TFNTwitterStatus*)object;
    }

    @try {
        id tweet = [object valueForKey:@"tweet"];
        if ([tweet isKindOfClass:(Class)objc_getClass("TFNTwitterStatus")]) {
            return (TFNTwitterStatus*)tweet;
        }
    } @catch (__unused NSException* exception) {
    }

    @
    try {
        id status = [object valueForKey:@"status"];
        if ([status isKindOfClass:(Class)objc_getClass("TFNTwitterStatus")]) {
            return (TFNTwitterStatus*)status;
        }
    } @catch (__unused NSException* exception) {
    }

    return nil;
}

void showPostSentAlert(NSString* statusID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* top = topMostController();
        if (!top) {
            return;
        }
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:
                [[BHTBundle sharedBundle]
                    localizedStringForKey:
                        @"COMPOSITION_COMPLETE_SENDING_TWEET_TOAST_NOTIFICATION_MESSAGE"]
                             message:nil
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                            localizedStringForKey:
                                                                @"DM_MESSAGE_ACTION_OPEN_GENERIC_TITLE"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction* action) {
                                                    openStatusNatively(statusID);
                                                }]];
        [alert
            addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                         localizedStringForKey:@"DISMISS_LABEL"]
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

BOOL openAuthenticatedTweetWebView(NSString* statusID) {
    if (statusID.length == 0) {
        return NO;
    }

    NSString* urlString =
        [NSString stringWithFormat:@"https://x.com/intent/tweet?in_reply_to=%@", statusID];
    NSURL* url = [NSURL URLWithString:urlString];
    if (!url) {
        return NO;
    }

    Class webViewControllerClass = (Class)objc_getClass("T1WebViewController");
    SEL initSel = @selector(initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:
                            sourceStatus:scribeComponent:scribeParameters:);
    if (!webViewControllerClass || ![webViewControllerClass instancesRespondToSelector:initSel]) {
        return NO;
    }

    id account = accountForAuthenticatedWebView();
    if (!account) {
        return NO;
    }

    UIViewController* presentingController = topMostController();
    if (!presentingController) {
        return NO;
    }

    T1WebViewController* webViewController = [[webViewControllerClass alloc] initWithRootURL:url
                                                                                     account:account
                                                                          shouldAuthenticate:YES
                                                                   shouldPresentAsNativePage:NO
                                                                                sourceStatus:nil
                                                                             scribeComponent:nil
                                                                            scribeParameters:nil];
    if (!webViewController) {
        return NO;
    }

    // Mark this instance so our -doesURLResultTypeOpenInWebview: and -setCurrentURL:
    // hooks know to keep the reply in-webview and auto-close it on /home.
    objc_setAssociatedObject(webViewController, KeepReplyInWebViewKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    Class navigationControllerClass = NSClassFromString(@"T1WebNavigationController")
                                          ?: (Class)objc_getClass("TFNNavigationController")
                                             ?
                                             : UINavigationController.class;
    UINavigationController* modalNavigationController =
        [[navigationControllerClass alloc] initWithRootViewController:webViewController];

    [presentingController presentViewController:modalNavigationController
                                       animated:YES
                                     completion:nil];

    return YES;
}
