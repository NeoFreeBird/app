#import "PostInteractions.h"

void BHTSetPostInteractionCounts(UIViewController* controller, TFNTwitterStatus* status) {
    if (status == nil || ![controller isViewLoaded]) {
        return;
    }
    if (![BHTSettings boolForKey:@"show_unrounded_quote_numbers"]) {
        NSString* titleFormat =
            [[BHTBundle sharedBundle] localizedStringForKey:@"POST_INTERACTIONS_COUNTS_TITLE"];
        controller.navigationItem.title = [NSString stringWithFormat:titleFormat,
                                                                     formatNumberWithSuffix(status.quoteCount),
                                                                     formatNumberWithSuffix(status.retweetCount)];
    } else {
        NSString* titleFormat = [[BHTBundle sharedBundle]
            localizedStringForKey:@"POST_INTERACTIONS_UNROUNDED_COUNTS_TITLE"];
        controller.navigationItem.title = [NSString stringWithFormat:titleFormat,
                                                                     status.quoteCount,
                                                                     status.retweetCount];
    }
}