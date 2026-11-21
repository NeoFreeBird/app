#import "MediaDownloads.h"

%hook AVURLAsset
- (id)initWithURL:(NSURL*)url options:(NSDictionary*)options {
    CaptureVoiceURL(url, @"AVURLAsset");
    return %orig;
}
%end

// AVAudioPlayer is covered as well as AVURLAsset because the Chat stack no
// longer has to build an AVPlayer to play a short local note.
%hook AVAudioPlayer
- (id)initWithContentsOfURL:(NSURL*)url error:(NSError**)outError {
    CaptureVoiceURL(url, @"AVAudioPlayer");
    return %orig;
}
- (id)initWithContentsOfURL:(NSURL*)url
               fileTypeHint:(NSString*)utiString
                      error:(NSError**)outError {
    CaptureVoiceURL(url, @"AVAudioPlayer/fileTypeHint");
    return %orig;
}
%end

%hook _TtC6ChatUI26MessageAttachmentAudioView

- (void)layoutSubviews {
    %orig;

    if (![BHTSettings boolForKey:@"download_voice_messages"] ||
        VoiceDownloadLongPressRecognizer(self) != nil) {
        return;
    }

    UILongPressGestureRecognizer* longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(nfb_handleVoiceDownloadLongPress:)];
    longPress.minimumPressDuration = 0.5;
    longPress.numberOfTouchesRequired = 2;
    longPress.cancelsTouchesInView = NO;

    [self addGestureRecognizer:longPress];
    SetVoiceDownloadLongPressRecognizer(self, longPress);
}

// The view overrides -gestureRecognizerShouldBegin: for its own waveform pan
// gesture, and UIKit routes that override through for *every* recognizer
// attached to the view -- ours included. Without this passthrough the long
// press installs cleanly and then never begins.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer {
    if (gestureRecognizer == VoiceDownloadLongPressRecognizer(self)) {
        return YES;
    }
    return %orig;
}

%new
- (void)nfb_handleVoiceDownloadLongPress:(UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }

    NSURL* voiceURL = nfbLastCapturedVoiceURL;
    if (voiceURL == nil) {
        return;
    }

    TFNActionItem* downloadItem = [objc_getClass("TFNActionItem")
        actionItemWithTitle:[[BHTBundle sharedBundle]
                                localizedStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                  imageName:@"arrow_down_circle_stroke"
                     action:^{
                         DownloadVoiceMessage(voiceURL);
                     }];

    TFNMenuSheetViewController* sheet = [[objc_getClass("TFNMenuSheetViewController") alloc]
        initWithActionItems:@[downloadItem]];

    [sheet tfnPresentedCustomPresentFromViewController:topMostController()
                                              animated:YES
                                            completion:nil];
}

%end

// MARK: - Save tweet as an image

%hook TTAStatusInlineShareButton
- (void)didLongPressActionButton:(UILongPressGestureRecognizer*)gestureRecognizer {
    if ([BHTSettings boolForKey:@"tweet_to_image"]) {
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
            UIView* statusView = self.superview;
            while (statusView && ![statusView respondsToSelector:@selector(eventHandler)]) {
                statusView = statusView.superview;
            }

            UIView* tweetView = nil;
            id eventHandler = [(T1StandardStatusView*)statusView eventHandler];
            if ([eventHandler isKindOfClass:UIView.class]) {
                tweetView = eventHandler;
            }

            if (tweetView == nil) {
                UIView* ancestor = self.superview;
                while (ancestor && ![ancestor isKindOfClass:UITableViewCell.class] &&
                       ![ancestor isKindOfClass:UICollectionViewCell.class]) {
                    ancestor = ancestor.superview;
                }
                tweetView = ancestor;
            }

            if (tweetView == nil) {
                return %orig;
            }

            UIImage* tweetImage = imageFromView(tweetView);
            NSData* pngData = UIImagePNGRepresentation(tweetImage);
            NSURL* pngURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]]];
            [pngData writeToURL:pngURL atomically:YES];
            UIActivityViewController* acVC =
                [[UIActivityViewController alloc] initWithActivityItems:@[pngURL]
                                                  applicationActivities:nil];
            if (is_iPad()) {
                acVC.popoverPresentationController.sourceView = self;
                acVC.popoverPresentationController.sourceRect = self.frame;
            }
            [topMostController() presentViewController:acVC animated:true completion:nil];
            return;
        }
    }
    return %orig;
}
%end

// MARK: - Tweet video download

// _t1_actionItemsForStatus:... is a category method on UIViewController, so the
// hook has to land on the base class to cover every share/action sheet.
%hook UIViewController
- (NSArray*)_t1_actionItemsForStatus:(__unsafe_unretained id)status
                             account:(__unsafe_unretained id)account
                     shareableEntity:(__unsafe_unretained id)shareableEntity
                           entityURL:(__unsafe_unretained id)entityURL
                              source:(__unsafe_unretained id)source
                             options:(NSUInteger)options
                     scribeComponent:(__unsafe_unretained id)scribeComponent
                           doneBlock:(__unsafe_unretained id)doneBlock {
    NSArray* origItems = %orig;

    if (![BHTSettings boolForKey:@"download_videos"] ||
        ![status respondsToSelector:@selector(entities)]) {
        return origItems;
    }

    NSArray* mediaEntities = [[status entities] media];
    BOOL hasVideo = NO;
    // mediaType 2 = GIF, 3 = video
    for (TFSTwitterEntityMedia* media in mediaEntities) {
        if ([media isKindOfClass:%c(TFSTwitterEntityMedia)] &&
            (media.mediaType == 2 || media.mediaType == 3)) {
            hasVideo = YES;
            break;
        }
    }
    if (!hasVideo) {
        return origItems;
    }

    static char downloaderKey;
    DownloadInlineButton* downloader = objc_getAssociatedObject(self, &downloaderKey);
    if (!downloader) {
        downloader = [%c(DownloadInlineButton) new];
        objc_setAssociatedObject(self, &downloaderKey, downloader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    TFNActionItem* downloadItem = [%c(TFNActionItem)
        actionItemWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"DOWNLOAD_VIDEOS_TITLE"]
                  imageName:@"arrow_down_circle_stroke"
                     action:^{
                         [downloader presentDownloadOptionsForMediaEntities:mediaEntities];
                     }];

    NSMutableArray* newItems = origItems ? [origItems mutableCopy] : [NSMutableArray array];
    NSUInteger insertIndex = newItems.count > 0 ? newItems.count - 1 : 0;
    [newItems insertObject:downloadItem atIndex:insertIndex];
    return newItems;
}
%end
