#import "ImmersivePlayer.h"

// MARK: - Immersive Player Timestamp

%hook _TtC14T1TwitterSwift17VideoControlsView

- (void)layoutSubviews {
    %orig;

    BHTApplyDimToVideoControls(self);

    if (![BHTSettings boolForKey:@"restore_video_timestamp"] ||
        objc_getAssociatedObject(self, kBHTRestoredTimestampKey)) {
        return;
    }

    Ivar modeIvar =
        class_getInstanceVariable([self class], "progressLabelMode");
    if (!modeIvar) {
        return;
    }

    objc_setAssociatedObject(self, kBHTRestoredTimestampKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Set once instead of on every layout so tapping the label still toggles
    // back to the remaining-time countdown.
    uint8_t* mode = (uint8_t*)(__bridge void*)self + ivar_getOffset(modeIvar);
    *mode = ProgressLabelModeTotal;
}

%end

%hook _TtC14T1TwitterSwift24ImmersivePiPDropZoneView
- (void)didMoveToWindow {
    %orig;
    if ([BHTSettings boolForKey:@"disable_video_docking"]) {
        self.hidden = true;
        self.alpha = 0.0;
        self.userInteractionEnabled = false;
        for (UIView* subview in self.subviews) {
            subview.hidden = true;
            subview.alpha = 0.0;
            subview.userInteractionEnabled = false;
        }
    }
}

%end

%hook T1ImmersiveViewController

- (BOOL)isCurrentCardDockEligible {
    if ([BHTSettings boolForKey:@"disable_video_docking"]) {
        return NO;
    }

    return %orig;
}

%end

// MARK: - Disable Immersive Feed Scrolling

%hook T1ImmersiveViewController

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gesture {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"] &&
        isImmersiveCardPan(self, gesture)) {
        if (isUpwardPan(gesture)) {
            return NO;
        }
        return YES;
    }

    return %orig;
}

- (BOOL)allowsUpwardSwipeToDismiss {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"]) {
        return NO;
    }

    return %orig;
}

- (void)handlePan:(UIPanGestureRecognizer*)pan {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"]) {
        CGPoint v = [pan velocityInView:self.view];
        if (v.y < 0.0) {
            return;
        }
    }

    %orig(pan);
}

%end

%hook T1ImmersiveViewControllerV2

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gesture {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"] &&
        isImmersiveCardPan(self, gesture)) {
        if (isUpwardPan(gesture)) {
            return NO;
        }
        return YES;
    }

    return %orig;
}

- (BOOL)allowsUpwardSwipeToDismiss {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"]) {
        return NO;
    }

    return %orig;
}

- (void)handlePan:(UIPanGestureRecognizer*)pan {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"]) {
        CGPoint v = [pan velocityInView:self.view];
        if (v.y < 0.0) {
            return;
        }
    }

    %orig(pan);
}

%end

// MARK: - Tap to Play/Pause

%hook _TtC14T1TwitterSwift17ImmersiveCardView

- (void)didMoveToWindow {
    %orig;

    if (!self.window || objc_getAssociatedObject(self, kBHTTwoFingerTapKey)) {
        return;
    }

    UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(bht_handleTwoFingerTap:)];
    tap.numberOfTouchesRequired = 2;
    tap.numberOfTapsRequired = 1;
    [self addGestureRecognizer:tap];

    objc_setAssociatedObject(self, kBHTTwoFingerTapKey, tap,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)bht_handleTwoFingerTap:(UITapGestureRecognizer*)tap {
    if (![BHTSettings boolForKey:@"tap_to_pause"]) {
        return;
    }

    __block UIView* pageView = nil;
    EnumerateSubviewsRecursively(self, ^(UIView* view) {
        if (!pageView &&
            [view isKindOfClass:%c(_TtC14T1TwitterSwift22ImmersiveVideoPageView)]) {
            pageView = view;
        }
    });

    TAVPlayer* player = pageView ? immersivePagePlayer(pageView) : nil;
    if (!player) {
        return;
    }

    BOOL wasPlaying = player.playbackState.timeControlStatus != 0;
    togglePlayback(player);

    [self setPausedByUser:wasPlaying];
}

%end
