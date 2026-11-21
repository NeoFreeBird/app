#import "Polls.h"

// "choice2_label" -> 2, anything else -> 0.
static NSUInteger BHTPollChoiceIndexForKey(NSString* key) {
    if (![key hasPrefix:@"choice"] || ![key hasSuffix:@"_label"]) {
        return 0;
    }

    NSRange digits = NSMakeRange(6, key.length - 6 - 6);
    NSInteger index = [key substringWithRange:digits].integerValue;
    return index > 0 ? (NSUInteger)index : 0;
}

static BOOL BHTPollAlreadyShowsResults(TFCCardData* cardData) {
    if ([cardData boolForKey:@"counts_are_final"]) {
        return YES;
    }

    return [cardData stringForKey:@"selected_choice"].length > 0;
}

static NSString* BHTPollPercentageString(double fraction) {
    static NSNumberFormatter* formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterPercentStyle;
        formatter.maximumFractionDigits = 0;
    });

    return [formatter stringFromNumber:@(fraction)];
}

NSString* BHTPollTitleWithPercentage(TFCCardData* cardData,
                                     NSString* key,
                                     NSString* title) {
    NSUInteger choice = BHTPollChoiceIndexForKey(key);
    if (choice == 0 || choice > BHTPollMaxChoices || title.length == 0 ||
        ![BHTSettings boolForKey:@"show_poll_results"]) {
        return title;
    }
    if (BHTPollAlreadyShowsResults(cardData)) {
        return title;
    }

    // numberForKey: tells a missing result apart from no votes
    long long total = 0;
    long long votes = 0;
    for (NSUInteger i = 1; i <= BHTPollMaxChoices; i++) {
        NSString* countKey =
            [NSString stringWithFormat:@"choice%lu_count", (unsigned long)i];
        NSNumber* count = [cardData numberForKey:countKey]
                              ?: [cardData numberFromStringForKey:countKey];
        if (!count) {
            continue;
        }

        total += count.longLongValue;
        if (i == choice) {
            votes = count.longLongValue;
        }
    }

    if (total <= 0) {
        return title;
    }

    return [NSString stringWithFormat:@"%@ (%@)", title,
                                      BHTPollPercentageString((double)votes /
                                                              (double)total)];
}
