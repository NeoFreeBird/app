#import "WebLinks.h"

// Every tapped link (Tweet text, link cards, profile bios) funnels into this one
// builder, which decides between the in-app browser, Safari and
// native navigation. Handing it the destination for both URLs means the t.co
// link never reaches the browser, and native x.com links open in the app.
%hook T1ViewControllerNavigationHelper

+ (id)_t1_handlerForURL:(NSURL*)url
             expandedURL:(NSURL*)expandedURL
                 account:(id)account
           scribeContext:(id)scribeContext
    sourceViewController:(id)sourceViewController
          webviewFactory:(id)webviewFactory {
    if (![url isKindOfClass:[NSURL class]]) {
        return %orig;
    }

    NSURL* destination = DestinationForLink(url, expandedURL);
    if (destination == url) {
        return %orig;
    }

    return %orig(destination, destination, account, scribeContext, sourceViewController,
                     webviewFactory);
}

%end

// Links built from URL entities (the visible text, copied links) use the
// destination too. The entity is also used for URLs that never had a t.co
// wrapper (e.g. share links), where expandedURL is nil.
%hook TFSTwitterEntityURL

- (NSString*)url {
    NSString* url = %orig;
    NSString* expandedURL = self.expandedURL;
    if (!BlocksLinkTracking() || expandedURL == nil) {
        return url;
    }

    RememberDestination(url, expandedURL);
    return expandedURL;
}

%end

// MARK: - Background t.co requests

%hook TNUTalonUtilities

// A HEAD request to the t.co link, sent alongside opening the destination so
// the click is still counted.
+ (BOOL)sendTalonRequestForAnalytics:(NSURL*)url {
    return BlocksLinkTracking() ? NO : %orig;
}

// Requests the t.co link to check it against Twitter's unsafe-link list. The
// completion gets the same result as for a link that isn't a t.co link (0),
// which leaves the in-app browser and app cards to carry on as normal.
+ (id)verifyTalonURL:(NSURL*)url completion:(void (^)(NSInteger result))completion {
    if (!BlocksLinkTracking() || !IsTalonURL(url)) {
        return %orig;
    }

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(0);
        });
    }
    return nil;
}

%end

// MARK: - Click IDs

// Promoted links get a twclid parameter tying the visit back to the click.
%hook T1TwitterClickIDHandler

+ (NSURL*)URLByAppendingTwitterClickIDIfNecessary:(NSURL*)url
                                           status:(id)status
                                          account:(id)account
                                       scribePage:(id)scribePage
                                  scribeComponent:(id)scribeComponent {
    return BlocksLinkTracking() ? url : %orig;
}

%end

%hook T1UnifiedCardBrowserDestinationHandlerHelper

- (id)openHandlerWithUrl:(NSURL*)url scribeContext:(id)scribeContext {
    if (!BlocksLinkTracking() || !IsTalonURL(url)) {
        return %orig;
    }

    id sourceStatus = ObjectForSelector(self, @selector(sourceStatus));
    NSURL* expandedURL = WebLinksExpandedURLForStatus(sourceStatus, url);
    NSURL* destination = DestinationForLink(url, expandedURL);

    if (destination == url) {
        return %orig;
    }
    return %orig(destination, scribeContext);
}

- (NSURL*)urlByAppendingTwitterClickIDToUrl:(NSURL*)url scribeComponent:(id)scribeComponent {
    return BlocksLinkTracking() ? url : %orig;
}

%end

%hook T1CardURLPresenter

- (id)openHandlerForURL:(NSURL*)url withPresentable:(id)presentable {
    if (!BlocksLinkTracking() || !IsTalonURL(url)) {
        return %orig;
    }

    if (![presentable respondsToSelector:@selector(cardDataSource)]) {
        return %orig;
    }
    id cardDataSource = ObjectForSelector(presentable, @selector(cardDataSource));
    NSURL* expandedURL = WebLinksExpandedURLForStatus(cardDataSource, url);
    NSURL* destination = DestinationForLink(url, expandedURL);
    if (destination == url) {
        return %orig;
    }
    return %orig(destination, presentable);
}

%end

%hook T1UnifiedCardXLinkDestinationHandlerHelper

- (NSURL*)urlByAppendingTwitterClickIDToUrl:(NSURL*)url scribeComponent:(id)scribeComponent {
    return BlocksLinkTracking() ? url : %orig;
}

%end

%hook TUCJobDetailsComponentModel

+ (id)conditionallyApplyPromotedContentClickID:(id)clickID toDestination:(id)destination {
    return BlocksLinkTracking() ? destination : %orig;
}

%end

// Advertiser links can be rerouted through a measurement-partner redirect that
// syncs an ad ID before landing on the destination.
%hook TFNTwitterAdsTPMIdSyncManager

- (BOOL)shouldCreateRedirectURLForURL:(NSURL*)url {
    return BlocksLinkTracking() ? NO : %orig;
}

- (NSURL*)createRedirectURLForURLIfNeeded:(NSURL*)url {
    return BlocksLinkTracking() ? url : %orig;
}

%end

// MARK: - Always open in Safari

// Every tapped link that resolves to the in-app Safari goes through this single
// present funnel, so diverting here avoids presenting anything at all.
%hook T1SafariViewController

- (void)tfnPresentedCustomPresentFromViewController:(UIViewController*)fromViewController
                                           animated:(BOOL)animated
                                         completion:(void (^)(void))completion {
    if (![BHTSettings boolForKey:@"always_open_safari"]) {
        return %orig;
    }

    NSURL* url = [self rootURL] ?: [self initialURL];
    if (url == nil || ShouldKeepBrowserURLInApp(url)) {
        return %orig;
    }

    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];

    if (completion) {
        completion();
    }
}

%end

// Fallback for the plain SFSafariViewController surfaces (help pages, Grok,
// XLinkWebView), which don't go through the T1SafariViewController funnel.
%hook SFSafariViewController

- (void)viewWillAppear:(BOOL)animated {
    if (![BHTSettings boolForKey:@"always_open_safari"]) {
        return %orig;
    }

    NSURL* url = [self initialURL];
    if (url == nil || ShouldKeepBrowserURLInApp(url)) {
        return %orig;
    }

    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    [self dismissViewControllerAnimated:NO completion:nil];
}

%end

// MARK: - Strip tracking params from shared links

// Profile links
%hook TFSTwitterUserReference

- (NSString*)twitterURLForShare {
    NSString* url = %orig;
    return CleanedShareURLString(url);
}

- (NSString*)twitterURLForCopy {
    NSString* url = %orig;
    return CleanedShareURLString(url);
}

%end

%hook TFNTwitterStatus

- (NSString*)twitterURLForShareWithSParam:(unsigned long long)sParam {
    NSString* url = %orig;
    return CleanedShareURLString(url);
}

+ (NSString*)twitterURLForShareWithSParam:(unsigned long long)sParam
                                 username:(NSString*)username
                                 statusID:(long long)statusID {
    NSString* url = %orig;
    return CleanedShareURLString(url);
}

%end

%ctor {
    %init;

    dispatch_async(dispatch_get_main_queue(), ^{
        Class pasteboardClass = object_getClass([UIPasteboard generalPasteboard]);
        if (pasteboardClass && class_getInstanceMethod(pasteboardClass, @selector(setString:))) {
            MSHookMessageEx(pasteboardClass, @selector(setString:),
                            (IMP)BHTPasteboardSetString,
                            (IMP*)&OriginalPasteboardSetString);
        }
    });
}
