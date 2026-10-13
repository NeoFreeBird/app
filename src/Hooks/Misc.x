//
//  Misc.x
//  NeoFreeBird
//

#import <CoreText/CoreText.h>
#import "HookHelpers.h"

// MARK: - Always open in Safari

// In-app browser is used for two-factor authentication with security key,
// login will not complete successfully if it's redirected to Safari
static BOOL ShouldKeepBrowserURLInApp(NSURL* url) {
    NSString* urlStr = [url absoluteString];

    return [urlStr containsString:@"twitter.com/account/"] ||
           [urlStr containsString:@"twitter.com/i/flow/"] ||
           [urlStr containsString:@"x.com/account/"] || [urlStr containsString:@"x.com/i/flow/"];
}

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

// MARK: - Disable RTL

// CoreText picks direction from the first strong directional character; forcing
// LTR on the render input's paragraph style is the only reliable override.

// CTParagraphStyle is immutable with no mutable counterpart, so forcing the
// writing direction means rebuilding the style with its specifiers copied over.
static CTParagraphStyleRef CreateLTRParagraphStyle(CTParagraphStyleRef original) {
    static const struct {
        CTParagraphStyleSpecifier specifier;
        size_t valueSize;
    } copiedSpecifiers[] = {
        {kCTParagraphStyleSpecifierAlignment, sizeof(CTTextAlignment)},
        {kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierHeadIndent, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierTailIndent, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierTabStops, sizeof(CFArrayRef)},
        {kCTParagraphStyleSpecifierDefaultTabInterval, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierLineBreakMode, sizeof(CTLineBreakMode)},
        {kCTParagraphStyleSpecifierLineHeightMultiple, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierMaximumLineHeight, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierMinimumLineHeight, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierLineSpacingAdjustment, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierMaximumLineSpacing, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierMinimumLineSpacing, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierParagraphSpacing, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(CGFloat)},
        {kCTParagraphStyleSpecifierLineBoundsOptions, sizeof(CTLineBoundsOptions)},
    };
    enum { copiedCount = sizeof(copiedSpecifiers) / sizeof(copiedSpecifiers[0]) };

    uint8_t values[copiedCount][sizeof(CFArrayRef)];
    CTParagraphStyleSetting settings[copiedCount + 1];
    size_t count = 0;

    for (size_t i = 0; i < copiedCount; i++) {
        if (CTParagraphStyleGetValueForSpecifier(original, copiedSpecifiers[i].specifier,
                                                 copiedSpecifiers[i].valueSize, values[count])) {
            settings[count] = (CTParagraphStyleSetting){copiedSpecifiers[i].specifier,
                                                        copiedSpecifiers[i].valueSize, values[count]};
            count++;
        }
    }

    CTWritingDirection direction = kCTWritingDirectionLeftToRight;
    settings[count++] = (CTParagraphStyleSetting){kCTParagraphStyleSpecifierBaseWritingDirection,
                                                  sizeof(direction), &direction};

    return CTParagraphStyleCreate(settings, count);
}

%hook TFNAttributedTextModel

- (void)setAttributedString:(NSAttributedString*)attributedString {
    if (![BHTSettings boolForKey:@"disable_rtl"] || attributedString.length == 0) {
        return %orig;
    }

    NSMutableAttributedString* text = [attributedString mutableCopy];
    [attributedString
        enumerateAttribute:NSParagraphStyleAttributeName
                   inRange:NSMakeRange(0, attributedString.length)
                   options:0
                usingBlock:^(id value, NSRange range, BOOL* stop) {
                    // Some models carry a raw CTParagraphStyleRef under the same key.
                    if (value != nil && ![value isKindOfClass:[NSParagraphStyle class]]) {
                        if (CFGetTypeID((__bridge CFTypeRef)value) == CTParagraphStyleGetTypeID()) {
                            CTParagraphStyleRef ltrStyle =
                                CreateLTRParagraphStyle((__bridge CTParagraphStyleRef)value);
                            [text addAttribute:NSParagraphStyleAttributeName
                                         value:(__bridge_transfer id)ltrStyle
                                         range:range];
                        }
                        return;
                    }

                    NSMutableParagraphStyle* style =
                        value ? [value mutableCopy] : [NSMutableParagraphStyle new];
                    style.baseWritingDirection = NSWritingDirectionLeftToRight;
                    [text addAttribute:NSParagraphStyleAttributeName value:style range:range];
                }];

    %orig(text);
}

%end

%hook NSString

- (BOOL)tfs_plainTextShouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

- (BOOL)tfs_statusTextShouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

- (BOOL)tfs_labelTextShouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

%end

%hook TFNTwitterStatus

- (BOOL)shouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

%end

%hook TFNTwitterDisplayTextModel

- (BOOL)_tfn_shouldBeRenderedFromRight {
    return [BHTSettings boolForKey:@"disable_rtl"] ? NO : %orig;
}

%end

// MARK: - Strip tracking params from shared links

// Strips the ?s= baked into the share URL format strings; &t= is already disabled
// at the source (rehire_share_update_url_enabled in FeatureSwitches.x).
static NSString* CleanedShareURLString(NSString* urlString) {
    if (urlString == nil) {
        return urlString;
    }

    NSURLComponents* components = [NSURLComponents componentsWithString:urlString];
    if (components == nil) {
        return urlString;
    }

    NSMutableArray<NSURLQueryItem*>* safeParams = [NSMutableArray arrayWithCapacity:0];
    for (NSURLQueryItem* item in components.queryItems) {
        if (![item.name isEqualToString:@"s"] && ![item.name isEqualToString:@"t"]) {
            [safeParams addObject:item];
        }
    }
    components.queryItems = safeParams.count > 0 ? safeParams : nil;

    NSString* selectedHost = [[NSUserDefaults standardUserDefaults] objectForKey:@"sharing_domain"];
    if (selectedHost.length > 0) {
        components.host = selectedHost;
    }

    return components.URL.absoluteString ?: urlString;
}

// Every share surface funnels into these two builders; the legacy twitterURLFor*
// selectors wrap the instance one and the Swift share kit calls it directly.
%hook TFNTwitterStatus

- (NSString*)twitterURLForShareWithSParam:(unsigned int)sParam {
    NSString* url = %orig;
    return CleanedShareURLString(url);
}

+ (NSString*)twitterURLForShareWithSParam:(unsigned int)sParam
                                 username:(NSString*)username
                                 statusID:(long long)statusID {
    NSString* url = %orig;
    return CleanedShareURLString(url);
}

%end

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

// MARK: - Disable screenshot and screen recording detection

%hook NSNotificationCenter

- (id)addObserverForName:(NSNotificationName)name
                  object:(id)obj
                   queue:(NSOperationQueue*)queue
              usingBlock:(void (^)(NSNotification* note))block {
    if ([name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) {
        return %orig(name, obj, queue,
                         ^(NSNotification* note){});
    }
    if ([name isEqualToString:UIScreenCapturedDidChangeNotification]) {
        return %orig(name, obj, queue,
                         ^(NSNotification* note){});
    }

    return %orig;
}

- (void)addObserver:(id)observer
           selector:(SEL)aSelector
               name:(NSNotificationName)aName
             object:(id)anObject {
    if ([aName isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) {
        return;
    }
    if ([aName isEqualToString:UIScreenCapturedDidChangeNotification]) {
        return;
    }

    return %orig;
}

%end

%hook UIScreen
- (BOOL)isCaptured {
    return NO;
}
%end

%hook TUIFollowControlCustomScreenshot
- (void)didMoveToWindow {
    %orig;
    self.hidden = true;
    self.alpha = 0.0;
    self.userInteractionEnabled = false;
}
%end


// MARK: Hide the refresh pill at the top of the page that appears when new tweets are available
%hook TFNPillControl
- (void)didMoveToWindow {
    %orig;

    if ([BHTSettings boolForKey:@"hide_timeline_prompts"]) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

%end

%hook TFNFloatingActionButton
- (void)didMoveToWindow {
    %orig;

    if ([BHTSettings boolForKey:@"hide_tweet_button"]) {
        self.userInteractionEnabled = NO;
        self.hidden = YES;
        self.alpha = 0.0;
    }
}

%end