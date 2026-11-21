#import "PostInteractions.h"
#import "../Fonts/Fonts.h"

@implementation BHTPostInteractionTitleLabel
@end

void BHTUpdatePostInteractionTitle(UIViewController* controller) {
    UIView* titleView = controller.navigationItem.titleView;
    if (![titleView isKindOfClass:[BHTPostInteractionTitleLabel class]]) {
        return;
    }

    UILabel* titleLabel = (UILabel*)titleView;
    NSDictionary* titleAttributes = controller.navigationController.navigationBar.titleTextAttributes;
    UIFont* baseFont = titleAttributes[NSFontAttributeName] ?: [UIFont boldSystemFontOfSize:17.0];
    UIFont* font = BHTReplaceFont(baseFont, YES);
    if (![titleLabel.font isEqual:font]) {
        titleLabel.font = font;
    }
    if (![titleLabel.text isEqualToString:controller.navigationItem.title]) {
        titleLabel.text = controller.navigationItem.title;
    }
    titleLabel.textColor = titleAttributes[NSForegroundColorAttributeName] ?: [UIColor labelColor];
}

void BHTSetPostInteractionCounts(UIViewController* controller, TFNTwitterStatus* status) {
    if (status == nil || ![controller isViewLoaded]) {
        return;
    }
    NSString* title;
    if (![BHTSettings boolForKey:@"show_unrounded_quote_numbers"]) {
        NSString* titleFormat =
            [[BHTBundle sharedBundle] localizedStringForKey:@"POST_INTERACTIONS_COUNTS_TITLE"];
        title = [NSString stringWithFormat:titleFormat,
                                           formatNumberWithSuffix(status.quoteCount),
                                           formatNumberWithSuffix(status.retweetCount)];
    } else {
        NSString* titleFormat = [[BHTBundle sharedBundle]
            localizedStringForKey:@"POST_INTERACTIONS_UNROUNDED_COUNTS_TITLE"];
        title = [NSString stringWithFormat:titleFormat, status.quoteCount, status.retweetCount];
    }

    controller.navigationItem.title = title;

    UILabel* titleLabel = [[BHTPostInteractionTitleLabel alloc] init];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.5;
    titleLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    controller.navigationItem.titleView = titleLabel;
    BHTUpdatePostInteractionTitle(controller);
    [titleLabel sizeToFit];
}
