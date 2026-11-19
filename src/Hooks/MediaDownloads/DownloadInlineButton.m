//
//  DownloadInlineButton.m
//  NeoFreeBird
//
//  Original author: BandarHelal at 09/04/2022
//  Modified by: actuallyaridan at 27/04/2025
//

#import "DownloadInlineButton.h"
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"

#pragma mark - Helpers
static UIWindow* KeyWindow(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class])
            continue;
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow)
                return window;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController* TopMostController(void) {
    UIViewController* top = KeyWindow().rootViewController;
    while (top.presentedViewController)
        top = top.presentedViewController;
    return top;
}

#pragma mark - DownloadInlineButton
@interface DownloadInlineButton ()
@property (nonatomic, strong) TFNHUD* hud;
@end

@implementation DownloadInlineButton

#pragma mark - Download handler
- (void)presentDownloadOptionsForMediaEntities:(NSArray*)mediaEntities {
    @try {
        NSAttributedString* titleString = [[NSAttributedString alloc]
            initWithString:[[BHTBundle sharedBundle]
                               localizedStringForKey:@"DOWNLOAD_MENU_TITLE"]
                attributes:@{
                    NSFontAttributeName: [BHTManager menuTitleFont],
                    NSForegroundColorAttributeName: UIColor.labelColor
                }];
        TFNActiveTextItem* title = [[objc_getClass("TFNActiveTextItem") alloc]
            initWithTextModel:[[objc_getClass("TFNAttributedTextModel") alloc]
                                  initWithAttributedString:titleString]
                 activeRanges:nil];

        void (^showHUD)(NSString*) = ^(NSString* text) {
            self.hud = [[objc_getClass("TFNHUD") alloc] initWithText:text];
            [self.hud show];
        };
        void (^dismissHUD)(void) = ^{
            [self.hud hide];
        };

        // Every download runs through FFmpeg: plain mp4s are stream-copied,
        // GIFs are palette-encoded, HLS-only resolutions are re-encoded with
        // VideoToolbox. The output path is appended to args; progress comes
        // from the processed time measured against the probed duration.
        NSString* downloadingText = [[BHTBundle sharedBundle]
            localizedStringForKey:@"DOWNLOAD_LIVE_ACTIVITY_DOWNLOADING"];
        void (^ffmpegDownload)(NSString*, NSString*, double, void (^)(void)) = ^(
            NSString* args, NSString* ext, double durationMs, void (^completion)(void)) {
            showHUD(downloadingText);
            NSURL* outFile = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.%@",
                                                                 NSUUID.UUID
                                                                     .UUIDString,
                                                                 ext]];
            [FFmpegKit
                executeAsync:[NSString stringWithFormat:@"%@ %@", args, outFile.path]
                withCompleteCallback:^(FFmpegSession* session) {
                    ReturnCode* returnCode = [session getReturnCode];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        dismissHUD();
                        UINotificationFeedbackGenerator* feedback =
                            [UINotificationFeedbackGenerator new];
                        [feedback prepare];

                        if ([ReturnCode isSuccess:returnCode]) {
                            if (![BHTSettings boolForKey:@"direct_save"]) {
                                [BHTManager showSaveVC:outFile];
                            } else {
                                [feedback
                                    notificationOccurred:UINotificationFeedbackTypeSuccess];
                                if ([ext isEqualToString:@"gif"])
                                    [BHTManager saveGIF:outFile];
                                else
                                    [BHTManager save:outFile];
                            }
                        } else {
                            [feedback notificationOccurred:UINotificationFeedbackTypeError];
                            UIAlertController* alert = [UIAlertController
                                alertControllerWithTitle:
                                    [[BHTBundle sharedBundle]
                                        localizedTwitterStringForKey:@"ERROR_ALERT_TITLE"]
                                                 message:[[BHTBundle sharedBundle]
                                                             localizedStringForKey:
                                                                 @"UNKNOWN_ERROR"]
                                          preferredStyle:UIAlertControllerStyleAlert];
                            [alert addAction:
                                       [UIAlertAction
                                           actionWithTitle:[[BHTBundle sharedBundle]
                                                               localizedTwitterStringForKey:
                                                                   @"OK_ACTION_LABEL"]
                                                     style:UIAlertActionStyleDefault
                                                   handler:nil]];
                            [TopMostController() presentViewController:alert
                                                              animated:YES
                                                            completion:nil];
                        }
                        if (completion)
                            completion();
                    });
                }
                withLogCallback:nil
                withStatisticsCallback:^(Statistics* statistics) {
                    NSString* detail;
                    if (durationMs > 0) {
                        detail = [BHTManager
                            getDownloadingPercent:MIN([statistics getTime] / durationMs,
                                                      1.0)];
                    } else if ([statistics getSize] > 0) {
                        detail = [NSByteCountFormatter
                            stringFromByteCount:[statistics getSize]
                                     countStyle:NSByteCountFormatterCountStyleFile];
                    } else {
                        return;
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.hud
                            setText:[NSString stringWithFormat:@"%@ %@", downloadingText,
                                                               detail]];
                    });
                }];
        };

        // Variant builders
        TFNActionItem* (^makeMP4Item)(NSURL*, double, NSString*) =
            ^TFNActionItem*(NSURL* url, double durationMs, NSString* itemTitle) {
                return [objc_getClass("TFNActionItem")
                    actionItemWithTitle:itemTitle
                              imageName:@"arrow_down_circle_stroke"
                                 action:^{
                                     ffmpegDownload(
                                         [NSString stringWithFormat:@"-i %@ -c copy",
                                                                    url.absoluteString],
                                         @"mp4", durationMs, nil);
                                 }];
            };

        TFNActionItem* (^makeGIFItem)(NSURL*, double) = ^TFNActionItem*(
            NSURL* url, double durationMs) {
            return [objc_getClass("TFNActionItem")
                actionItemWithTitle:
                    [[BHTBundle sharedBundle]
                        localizedStringForKey:@"DOWNLOAD_AS_GIF_OPTION_TITLE"]
                          imageName:@"arrow_down_circle_stroke"
                             action:^{
                                 ffmpegDownload(
                                     [NSString
                                         stringWithFormat:@"-i %@ -an -vf "
                                                          @"split[a][b];[a]palettegen["
                                                          @"p];[b][p]paletteuse",
                                                          url.absoluteString],
                                     @"gif", durationMs, nil);
                             }];
        };

        TFNActionItem* (^makeHLSItem)(NSURL*, NSString*, double) = ^TFNActionItem*(
            NSURL* url, NSString* resolution, double durationMs) {
            return [objc_getClass("TFNActionItem")
                actionItemWithTitle:resolution
                          imageName:@"arrow_down_circle_stroke"
                             action:^{
                                 ffmpegDownload(
                                     [NSString
                                         stringWithFormat:
                                             @"-i %@ -vf scale=%@:flags=lanczos -c:v "
                                             @"h264_videotoolbox -b:v 2M -c:a copy",
                                             url.absoluteString, resolution],
                                     @"mp4", durationMs, nil);
                             }];
        };

        // Picks the mp4 variant with the most pixels, or nil if there is none.
        NSURL* (^bestMP4URL)(TFSTwitterEntityMedia*) = ^NSURL*(
            TFSTwitterEntityMedia* media) {
            NSURL* bestURL = nil;
            NSInteger bestPixels = -1;
            for (TFSTwitterEntityMediaVideoVariant* variant in media.videoInfo
                     .variants) {
                NSURL* url =
                    variant.url.length ? [NSURL URLWithString:variant.url] : nil;
                if (!url || ![variant.contentType isEqualToString:@"video/mp4"])
                    continue;

                NSArray<NSString*>* dims =
                    [[BHTManager getVideoQuality:url.absoluteString]
                        componentsSeparatedByString:@"x"];
                NSInteger pixels =
                    dims.count == 2 ? dims[0].integerValue * dims[1].integerValue : 0;
                if (pixels > bestPixels) {
                    bestPixels = pixels;
                    bestURL = url;
                }
            }
            return bestURL;
        };

        // videoInfo.variants backs both video (mediaType 3) and GIF (mediaType 2);
        // photos carry no videoInfo. Probing the playlist supplies the duration
        // for progress and any HLS-only resolutions, so every quality is offered
        // in a single sheet. mp4 variants win when both carry the same
        // resolution; media without a playlist (GIFs) skips the probe entirely.
        void (^buildVariantItems)(TFSTwitterEntityMedia*, void (^)(NSArray*)) = ^(
            TFSTwitterEntityMedia* media, void (^done)(NSArray*)) {
            NSMutableArray<NSURL*>* mp4URLs = [NSMutableArray new];
            NSURL* m3u8URL = nil;
            for (TFSTwitterEntityMediaVideoVariant* variant in media.videoInfo
                     .variants) {
                NSURL* url =
                    variant.url.length ? [NSURL URLWithString:variant.url] : nil;
                if (!url)
                    continue;

                if ([variant.contentType isEqualToString:@"video/mp4"])
                    [mp4URLs addObject:url];
                else if ([variant.contentType
                             isEqualToString:@"application/x-mpegURL"] &&
                         !m3u8URL)
                    m3u8URL = url;
            }

            if ([BHTSettings boolForKey:@"download_highest_quality"] &&
                media.mediaType == 3 && mp4URLs.count > 0) {
                ffmpegDownload(
                    [NSString stringWithFormat:@"-i %@ -c copy",
                                               bestMP4URL(media).absoluteString],
                    @"mp4", 0, nil);
                return;
            }

            NSMutableArray* items = [NSMutableArray new];
            NSMutableSet<NSString*>* offered = [NSMutableSet new];
            void (^appendMP4Items)(double) = ^(double durationMs) {
                BOOL isGIF = media.mediaType == 2;
                for (NSURL* url in mp4URLs) {
                    NSString* itemTitle =
                        isGIF ? [[BHTBundle sharedBundle]
                                    localizedStringForKey:@"DOWNLOAD_AS_MP4_OPTION_TITLE"]
                              : [BHTManager getVideoQuality:url.absoluteString];
                    [offered addObject:[BHTManager getVideoQuality:url.absoluteString]];
                    [items addObject:makeMP4Item(url, durationMs, itemTitle)];
                    if (isGIF)
                        [items addObject:makeGIFItem(url, durationMs)];
                }
            };

            if (!m3u8URL) {
                appendMP4Items(0);
                done(items);
                return;
            }

            showHUD([[BHTBundle sharedBundle]
                localizedStringForKey:@"FETCHING_PROGRESS_TITLE"]);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                MediaInformation* info = [BHTManager getM3U8Information:m3u8URL];
                double durationMs = [info getDuration].doubleValue * 1000.0;

                dispatch_async(dispatch_get_main_queue(), ^{
                    dismissHUD();
                    appendMP4Items(durationMs);
                    for (StreamInformation* stream in [info getStreams]) {
                        NSNumber* width = [stream getWidth];
                        NSNumber* height = [stream getHeight];
                        if (width == nil || height == nil)
                            continue;

                        NSString* resolution =
                            [NSString stringWithFormat:@"%@x%@", width, height];
                        if ([offered containsObject:resolution])
                            continue;

                        [offered addObject:resolution];
                        [items addObject:makeHLSItem(m3u8URL, resolution, durationMs)];
                    }
                    done(items);
                });
            });
        };

        // Filter to video/GIF so grouping keys off the real video count, not the
        // raw media count.
        NSMutableArray<TFSTwitterEntityMedia*>* videoEntities =
            [NSMutableArray new];
        for (TFSTwitterEntityMedia* media in mediaEntities) {
            if ((media.mediaType == 2 || media.mediaType == 3) &&
                media.videoInfo.variants.count > 0) {
                [videoEntities addObject:media];
            }
        }

        void (^presentSheet)(NSArray*) = ^(NSArray* items) {
            NSMutableArray* actions = [NSMutableArray arrayWithObject:title];
            [actions addObjectsFromArray:items];

            TFNMenuSheetViewController* sheet =
                [[objc_getClass("TFNMenuSheetViewController") alloc]
                    initWithActionItems:actions.copy];
            [sheet tfnPresentedCustomPresentFromViewController:TopMostController()
                                                      animated:YES
                                                    completion:nil];
        };

        if (videoEntities.count > 1) {
            NSMutableArray* groups = [NSMutableArray new];
            [videoEntities enumerateObjectsUsingBlock:^(TFSTwitterEntityMedia* media,
                                                        NSUInteger idx, BOOL* stop) {
                [groups
                    addObject:[objc_getClass("TFNActionItem")
                                  actionItemWithTitle:
                                      [NSString
                                          stringWithFormat:
                                              [[BHTBundle sharedBundle]
                                                  localizedStringForKey:
                                                      @"DOWNLOAD_VIDEO_NUMBER_TITLE"],
                                              (unsigned long)idx + 1]
                                            imageName:@"arrow_down_circle_stroke"
                                               action:^{
                                                   buildVariantItems(media, presentSheet);
                                               }]];
            }];
            // Offer a single item that grabs the best mp4 of every video. Downloads
            // run one after another since they share the HUD and save sheet.
            BOOL allVideos = YES;
            for (TFSTwitterEntityMedia* media in videoEntities) {
                if (media.mediaType != 3) {
                    allVideos = NO;
                    break;
                }
            }
            if (allVideos && [BHTSettings boolForKey:@"download_all_videos"]) {
                NSArray<TFSTwitterEntityMedia*>* queue = videoEntities.copy;
                [groups
                    insertObject:[objc_getClass("TFNActionItem")
                                     actionItemWithTitle:
                                         [[BHTBundle sharedBundle]
                                             localizedStringForKey:
                                                 @"DOWNLOAD_ALL_VIDEOS_OPTION_TITLE"]
                                               imageName:@"arrow_down_circle_stroke"
                                                  action:^{
                                                      __block void (^downloadNext)(NSUInteger);
                                                      downloadNext = ^(NSUInteger idx) {
                                                          if (idx >= queue.count) {
                                                              downloadNext = nil;
                                                              return;
                                                          }
                                                          NSURL* url = bestMP4URL(queue[idx]);
                                                          if (!url) {
                                                              downloadNext(idx + 1);
                                                              return;
                                                          }
                                                          ffmpegDownload(
                                                              [NSString
                                                                  stringWithFormat:@"-i %@ -c copy",
                                                                                   url.absoluteString],
                                                              @"mp4", 0, ^{
                                                                  downloadNext(idx + 1);
                                                              });
                                                      };
                                                      downloadNext(0);
                                                  }]
                         atIndex:0];
            }
            presentSheet(groups);
        } else {
            buildVariantItems(videoEntities.firstObject, presentSheet);
        }
    } @catch (__unused NSException* ex) {
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:
                [[BHTBundle sharedBundle]
                    localizedTwitterStringForKey:@"ERROR_ALERT_TITLE"]
                             message:[[BHTBundle sharedBundle]
                                         localizedStringForKey:@"UNKNOWN_ERROR"]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
                             actionWithTitle:[[BHTBundle sharedBundle]
                                                 localizedTwitterStringForKey:
                                                     @"OK_ACTION_LABEL"]
                                       style:UIAlertActionStyleDefault
                                     handler:nil]];
        [TopMostController() presentViewController:alert
                                          animated:YES
                                        completion:nil];
    }
}

@end
