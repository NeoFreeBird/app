#import "MediaView.h"

// MARK: - Force tweet images to full frame

%hook T1StandardStatusAttachmentViewAdapter

// attachmentType 2 = photos, displayType 1 = full frame
- (NSUInteger)displayType {
    if (self.attachmentType == 2) {
        return [BHTSettings boolForKey:@"force_tweet_full_frame"] ? 1 : %orig;
    }

    return %orig;
}

// Attachment types 2, 3, and 4 are photo, video, and GIF media respectively.
// Returning NO removes only the inline attachment; the post itself remains
// available to open, where the media can still be viewed.
- (BOOL)shouldBeVisibleForViewModel:(id)viewModel {
    BOOL visible = %orig;
    if (!visible || ![BHTSettings boolForKey:@"hide_media_previews"]) {
        return visible;
    }

    NSUInteger attachmentType = self.attachmentType;
    return attachmentType != 2 && attachmentType != 3 && attachmentType != 4;
}

%end

%hook T1AccountAutoplayPolicy

- (id)initWithCurrentSettings:(id)settings
           currentNetworkReachabilityStatus:(id)status
                         notificationCenter:(id)center
    ignoreCurrentSettingsWhenAutoplayingGif:(_Bool)ignore {
    return %orig(settings, status, center, NO);
}

- (id)initWithIgnoreCurrentSettingsWhenAutoplayingGif:(_Bool)ignore {
    return %orig(NO);
}

%end
