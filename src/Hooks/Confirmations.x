//
//  Confirmations.x
//  NeoFreeBird
//

#import <AVFoundation/AVFoundation.h>
#import "HookHelpers.h"

static void PlayCustomSendSound(void) {
    NSString* path = [[NSUserDefaults standardUserDefaults] stringForKey:@"custom_send_sound_path"];
    if (path.length == 0) {
        return;
    }

    static AVAudioPlayer* player;
    NSError* error = nil;
    player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                    error:&error];
    if (player && [player prepareToPlay]) {
        [player play];
    }
}

// Set while a block confirmation alert is expected, so the alert can be
// answered without being shown (Fast block/mute, below).
static BOOL awaitingBlockAlert = NO;
static char kBlockConfirmHandlerKey;

static void ShowConfirmation(void (^confirmed)(void)) {
    [%c(FLEXAlert)
        makeAlert:^(FLEXAlert* make) {
            make.message([[BHTBundle sharedBundle]
                localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);

            make.button([[BHTBundle sharedBundle]
                            localizedStringForKey:@"YES_ACTION_LABEL"])
                .handler(^(NSArray<NSString*>* strings) {
                    confirmed();
                });

            make.button([[BHTBundle sharedBundle]
                            localizedStringForKey:@"NO_ACTION_LABEL"])
                .cancelStyle();
        }
         showFrom:topMostController()];
}

// MARK: - Tweet confirm

// All send paths funnel through this. Some callers send no argument, so the
// button register can hold garbage and must not be retained.
%hook T1TweetComposeViewController

- (void)_t1_didTapSendButton:(__unsafe_unretained UIButton*)sendButton {
    if (![BHTSettings boolForKey:@"tweet_confirm"]) {
        PlayCustomSendSound();
        return %orig;
    }

    ShowConfirmation(^{
        PlayCustomSendSound();
        %orig;
    });
}

%end

%hook T1PersistentComposeViewController
- (void)_t1_sendReply {
    if (![BHTSettings boolForKey:@"tweet_confirm"]) {
        PlayCustomSendSound();
        return %orig;
    }

    ShowConfirmation(^{
        PlayCustomSendSound();
        %orig;
    });
}

%end

// MARK: - Follow confirm

%hook TUIFollowControl

- (void)_followUser:(id)sender event:(id)event {
    if (![BHTSettings boolForKey:@"follow_confirm"]) {
        return %orig;
    }

    ShowConfirmation(^{
        %orig;
    });
}

%end

%hook TUIFollowButtonV2

- (void)buttonTapped {
    if (![BHTSettings boolForKey:@"follow_confirm"]) {
        return %orig;
    }

    ShowConfirmation(^{
        %orig;
    });
}

%end

// MARK: - Like confirm

// didTap on every inline action button routes through this delegate method,
// so only intercept the favorite button.
%hook TTAStatusInlineActionsView

- (void)didTapInlineActionButton:(UIView*)button {
    if (![BHTSettings boolForKey:@"like_confirm"] ||
        ![button isKindOfClass:%c(TTAStatusInlineFavoriteButton)]) {
        return %orig;
    }

    ShowConfirmation(^{
        %orig;
    });
}

%end

// The fullscreen media viewer's heart has its own action path.
%hook T1SlideshowStatusView

- (void)_favoriteAction:(id)sender {
    if (![BHTSettings boolForKey:@"like_confirm"]) {
        return %orig;
    }

    ShowConfirmation(^{
        %orig;
    });
}

%end

// Double tap to like in the immersive video player; the gesture never unlikes.
%hook _TtC14T1TwitterSwift32ImmersiveDoubleTapLikePluginView

- (void)handleDoubleTap:(id)gesture {
    if (![BHTSettings boolForKey:@"like_confirm"]) {
        return %orig;
    }

    ShowConfirmation(^{
        %orig;
    });
}

%end

// MARK: - Fast block/mute

static BOOL FastBlockEnabled(void) {
    return [BHTSettings boolForKey:@"fast_block"];
}

%hook TFNTwitterAccount

- (BOOL)isXDSAlertBlockUserEnabled {
    return FastBlockEnabled() ? NO : %orig;
}

- (BOOL)shouldDisplayUserMuteConfirmationAlert {
    return FastBlockEnabled() ? NO : %orig;
}

%end

%hook T1BlockMuteActionPerformer

- (void)showBlockAlertForContext:(id)context {
    BOOL saved = awaitingBlockAlert;
    awaitingBlockAlert = FastBlockEnabled();
    @try {
        %orig;
    } @finally {
        awaitingBlockAlert = saved;
    }
}

%end

// The mute alert is requested by the caller rather than by the mute itself.
%hook T1TabbedAppNavigation

- (void)muteActionForUser:(id)user
                    isMuting:(BOOL)muting
    showConfirmationIfNeeded:(BOOL)needed
                impressionID:(id)impressionID
                  isPromoted:(BOOL)promoted
                    isEarned:(BOOL)earned
                  scribePage:(id)page
               scribeSection:(id)section
             scribeComponent:(id)component
            scribeParameters:(id)parameters
                  completion:(id)completion {
    %orig(user, muting, FastBlockEnabled() ? NO : needed, impressionID, promoted,
              earned, page, section, component, parameters, completion);
}

- (void)_showBlockStatusForContext:(id)context source:(long long)source {
    BOOL saved = awaitingBlockAlert;
    awaitingBlockAlert = FastBlockEnabled();
    @try {
        %orig;
    } @finally {
        awaitingBlockAlert = saved;
    }
}

- (void)_showBlockMessageForContext:(id)context source:(long long)source {
    BOOL saved = awaitingBlockAlert;
    awaitingBlockAlert = FastBlockEnabled();
    @try {
        %orig;
    } @finally {
        awaitingBlockAlert = saved;
    }
}

%end

%hook UIAlertController

// Both block alerts get their cancel action from the constructor and add
// exactly one destructive action, which is the one that does the blocking.
- (id)tfn_addActionWithTitle:(NSString*)title
                       style:(UIAlertActionStyle)style
                     handler:(void (^)(void))handler {
    if (awaitingBlockAlert && style == UIAlertActionStyleDestructive && handler) {
        objc_setAssociatedObject(self, &kBlockConfirmHandlerKey, handler,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return %orig;
}

- (void)tfn_presentFromViewController:(UIViewController*)viewController {
    if (!awaitingBlockAlert) {
        return %orig;
    }
    // Anything else reaching presentation while armed — an error alert raised
    // during the dismissal, say — has no captured handler and is left alone.
    void (^confirm)(void) = objc_getAssociatedObject(self, &kBlockConfirmHandlerKey);
    if (!confirm) {
        return %orig;
    }

    awaitingBlockAlert = NO;
    objc_setAssociatedObject(self, &kBlockConfirmHandlerKey, nil,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    confirm();
}

%end

// Block from the follow control on profiles and user rows, which shows a menu
// sheet rather than an alert. Its action calls -_doBlockUser:event:, so the
// sheet can be skipped by going there directly.
%hook TUIFollowControl

- (void)_blockUser:(id)user event:(id)event {
    if (!FastBlockEnabled()) {
        return %orig;
    }
    [self _doBlockUser:user event:event];
}

- (void)_unblockUser:(id)user event:(id)event {
    if (!FastBlockEnabled()) {
        return %orig;
    }
    [self _doUnblockUser:user event:event];
}

- (void)_blockMessageUser:(id)user event:(id)event {
    if (!FastBlockEnabled()) {
        return %orig;
    }
    [self _doBlockMessageUser:user event:event];
}

- (void)_unblockMessageUser:(id)user event:(id)event {
    if (!FastBlockEnabled()) {
        return %orig;
    }
    [self _doUnblockMessageUser:user event:event];
}

%end

%hook TUIFollowButtonV2

- (void)setConfirmBlock:(BOOL)confirmBlock {
    %orig(FastBlockEnabled() ? NO : confirmBlock);
}

- (BOOL)confirmBlock {
    return FastBlockEnabled() ? NO : %orig;
}

%end

// MARK: - Undo tweet

// A timeout of 0 disables undo; any positive value is the delay in seconds.
static BOOL UndoTweetEnabled(void) {
    return [BHTSettings integerForKey:@"undo_tweet_timeout"] > 0;
}

// Force every composition onto the premium undo path (outbox timer, no cap) —
// the free path is just a toast, capped at 10s. Forcing config access and the
// per-type toggles marks it undoable; the forced undoTimeInterval becomes the
// real send delay.
%hook T1UndoSendConfig

- (BOOL)hasAccessToUndoSend {
    return UndoTweetEnabled() ? YES : %orig;
}

- (double)undoTimeInterval {
    return UndoTweetEnabled()
               ? (double)[BHTSettings integerForKey:@"undo_tweet_timeout"]
               : %orig;
}

- (BOOL)isUndoSendTurnedOnForOriginalTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForReplyTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForQuoteTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForTweetstormTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForPollTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

%end

// The composer bakes the config's interval onto the composition; override the
// read too so the coordinator's send timer uses the chosen value.
%hook TFNTwitterComposition

- (double)undoTimeInterval {
    return UndoTweetEnabled()
               ? (double)[BHTSettings integerForKey:@"undo_tweet_timeout"]
               : %orig;
}

// The original computes this from the interval directly, bypassing the getter.
- (NSDate*)undoableSendDate {
    if (!UndoTweetEnabled()) {
        return %orig;
    }
    NSDate* added = [self undoableAddedDate];
    return added ? [added dateByAddingTimeInterval:[self undoTimeInterval]] : nil;
}

%end
