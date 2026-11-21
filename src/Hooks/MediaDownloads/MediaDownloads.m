#import "MediaDownloads.h"

static BOOL IsVoiceMediaURL(NSURL* url) {
    if (url == nil) {
        return NO;
    }
    if ([url.path containsString:@"/decrypted-media-v2/"]) {
        return YES;
    }
    static NSSet* audioExtensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioExtensions = [NSSet setWithArray:@[@"m4a", @"aac", @"caf", @"wav", @"mp3"]];
    });
    return [audioExtensions containsObject:url.pathExtension.lowercaseString];
}

void CaptureVoiceURL(NSURL* url, NSString* source) {
    if (![BHTSettings boolForKey:@"download_voice_messages"]) {
        return;
    }
    BOOL kept = IsVoiceMediaURL(url);
    NSLog(@"[NFB] voice capture (%@) %@: %@", source, kept ? @"kept" : @"ignored", url);
    if (kept) {
        nfbLastCapturedVoiceURL = url;
    }
}

// DM voice notes are pre-decrypted straight to disk (Documents/dm/.../
// decrypted-media-v2/.../*.m4a), so we just need to copy the file here.
void DownloadVoiceMessage(NSURL* sourceURL) {
    NSString* extension = sourceURL.pathExtension.length ? sourceURL.pathExtension : @"m4a";
    NSURL* destination = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString
                                        stringWithFormat:@"%@.%@", NSUUID.UUID.UUIDString, extension]];

    if (sourceURL.isFileURL) {
        NSError* copyError = nil;
        [[NSFileManager defaultManager] copyItemAtURL:sourceURL toURL:destination error:&copyError];
        if (copyError) {
            NSLog(@"[NFB] DownloadVoiceMessage copy failed: %@", copyError);
            return;
        }
        [BHTManager showSaveVC:destination];
        return;
    }

    TFNHUD* hud = [[objc_getClass("TFNHUD") alloc]
        initWithText:[[BHTBundle sharedBundle]
                         localizedStringForKey:@"DOWNLOAD_LIVE_ACTIVITY_DOWNLOADING"]];
    [hud show];
    NSURLSessionDownloadTask* task = [[NSURLSession sharedSession]
        downloadTaskWithURL:sourceURL
          completionHandler:^(NSURL* location, NSURLResponse* response, NSError* error) {
              dispatch_async(dispatch_get_main_queue(), ^{
                  [hud hide];
                  if (!location || error) {
                      return;
                  }
                  NSError* moveError = nil;
                  [[NSFileManager defaultManager] moveItemAtURL:location toURL:destination error:&moveError];
                  if (moveError) {
                      return;
                  }
                  [BHTManager showSaveVC:destination];
              });
          }];
    [task resume];
}

NSArray* DMVideoEntities(UIView* attachmentView) {
    NSMutableArray* entities = [NSMutableArray new];

    EnumerateSubviewsRecursively(attachmentView, ^(UIView* view) {
        if (![view respondsToSelector:@selector(inlineMediaInfos)]) {
            return;
        }

        for (TFSTwitterMediaInfo* info in
             [(_TtC21TweetMediaAttachments14MultiMediaView*)view inlineMediaInfos]) {
            TFSTwitterEntityMedia* media = info.mediaEntity;
            if (media.videoInfo.variants.count > 0) {
                [entities addObject:media];
            }
        }
    });

    return [entities copy];
}

UILongPressGestureRecognizer* VoiceDownloadLongPressRecognizer(UIView* view) {
    return objc_getAssociatedObject(view, kVoiceDownloadLongPressKey);
}

void SetVoiceDownloadLongPressRecognizer(UIView* view,
                                         UILongPressGestureRecognizer* recognizer) {
    objc_setAssociatedObject(view, kVoiceDownloadLongPressKey, recognizer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
