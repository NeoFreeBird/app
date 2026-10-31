//
//  Branding.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Restore Twitter terminology
// Two layers, both driven by locale files in the tweak bundle:
//   1. RenameOverrides.strings — Twitter localization key -> exact replacement,
//      a missing key falls through to the generic replacement
//   2. RenameWords.strings — generic word replacements ("X" -> "Twitter",
//      "Post" -> "Tweet", etc.) applied to localized and server-side strings
// Both are strictly per-language: a language without its own copy of a file
// gets no renaming from that layer, rather than English rules applied to
// non-English text.

static NSDictionary<NSString*, NSString*>* RenameTable(NSString* name) {
    NSBundle* bundle = [BHTBundle sharedBundle].mainBundle;
    NSString* appLanguage =
        [[NSBundle mainBundle] preferredLocalizations].firstObject ?: @"en";
    NSString* localization =
        [NSBundle preferredLocalizationsFromArray:bundle.localizations
                                   forPreferences:@[appLanguage]]
            .firstObject;

    // preferredLocalizationsFromArray: falls back to en when nothing matches, so
    // reject a mismatch: unsupported languages skip renaming, not get English
    // rules.
    NSString* appCode =
        [appLanguage componentsSeparatedByString:@"-"].firstObject;
    NSString* lprojCode =
        [[localization stringByReplacingOccurrencesOfString:@"_" withString:@"-"]
            componentsSeparatedByString:@"-"]
            .firstObject;
    if (![appCode isEqualToString:lprojCode]) {
        return @{};
    }

    NSString* path = [bundle pathForResource:name
                                      ofType:@"strings"
                                 inDirectory:nil
                             forLocalization:localization];
    NSString* contents =
        path ? [NSString stringWithContentsOfFile:path
                                         encoding:NSUTF8StringEncoding
                                            error:nil]
             : nil;
    NSDictionary* table = [contents propertyListFromStringsFileFormat];
    return [table isKindOfClass:[NSDictionary class]] ? table : @{};
}

static NSDictionary<NSString*, NSString*>* RenameKeyOverrides(void) {
    static NSDictionary* overrides = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        overrides = RenameTable(@"RenameOverrides");
    });
    return overrides;
}

static NSDictionary<NSString*, NSString*>* TwitterWordMap(void) {
    static NSDictionary* map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = RenameTable(@"RenameWords");
    });
    return map;
}

// Builds a case-insensitive \b(word|word…)\b from the map keys, longest first
// so inflections win over their stems. Exact case for uppercase-bearing keys is
// enforced per match in RenameEdits, so lowercase "x" never becomes "Twitter".
static NSRegularExpression* RenameRegex(void) {
    NSMutableArray<NSString*>* words = [NSMutableArray array];
    for (NSString* word in TwitterWordMap()) {
        [words addObject:[NSRegularExpression escapedPatternForString:word]];
    }
    if (words.count == 0) {
        return nil;
    }

    [words sortUsingComparator:^NSComparisonResult(NSString* a, NSString* b) {
        if (a.length > b.length)
            return NSOrderedAscending;
        if (a.length < b.length)
            return NSOrderedDescending;
        return [a compare:b];
    }];
    NSString* pattern = [NSString
        stringWithFormat:@"\\b(%@)\\b", [words componentsJoinedByString:@"|"]];
    return [NSRegularExpression
        regularExpressionWithPattern:pattern
                             options:NSRegularExpressionCaseInsensitive
                               error:nil];
}

// Applies the capitalisation style of `token` (all-caps or leading-capital) to
// `base`.
static NSString* MatchCapitalisation(NSString* token, NSString* base) {
    if (token.length == 0 || base.length == 0) {
        return base;
    }

    NSString* lower = token.lowercaseString;
    if (token.length > 1 && [token isEqualToString:token.uppercaseString] &&
        ![token isEqualToString:lower]) {
        return base.uppercaseString;
    }

    unichar first = [token characterAtIndex:0];
    if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:first]) {
        return [base stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                             withString:[base substringToIndex:1]
                                                            .uppercaseString];
    }
    return base;
}

// Returns the edits (@"range" -> NSValue, @"repl" -> NSString) in ascending,
// non-overlapping order — apply them back-to-front. Nil when nothing changes.
static NSArray<NSDictionary*>* RenameEdits(NSString* input) {
    if (input.length == 0) {
        return nil;
    }

    static NSRegularExpression* regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = RenameRegex();
    });
    if (!regex) {
        return nil;
    }

    NSDictionary* wordMap = TwitterWordMap();
    NSRange full = NSMakeRange(0, input.length);
    NSMutableArray<NSDictionary*>* edits = [NSMutableArray array];

    for (NSTextCheckingResult* match in [regex matchesInString:input
                                                       options:0
                                                         range:full]) {
        NSString* token = [input substringWithRange:match.range];
        // Exact key wins; otherwise fall back to the lowercase key and copy the
        // token's capitalisation. A lowercase hit on an uppercase-only key is left
        // alone.
        NSString* repl = wordMap[token];
        if (!repl) {
            NSString* base = wordMap[token.lowercaseString];
            repl = base ? MatchCapitalisation(token, base) : nil;
        }
        if (repl) {
            [edits addObject:@{
                @"range": [NSValue valueWithRange:match.range],
                @"repl": repl
            }];
        }
    }

    return edits.count > 0 ? edits : nil;
}

static NSString* RestoreTwitterTerminology(NSString* input) {
    NSArray<NSDictionary*>* edits = RenameEdits(input);
    if (!edits) {
        // Plural formats from .stringsdict may have identical text but carry
        // different localization metadata. Preserve the original string object.
        return input;
    }

    NSMutableString* result = [input mutableCopy];
    for (NSDictionary* edit in edits.reverseObjectEnumerator) {
        [result replaceCharactersInRange:[edit[@"range"] rangeValue]
                              withString:edit[@"repl"]];
    }
    return [result copy];
}

static NSAttributedString* RestoreTwitterAttributed(NSAttributedString* input) {
    NSArray<NSDictionary*>* edits = RenameEdits(input.string);
    if (!edits) {
        return input;
    }

    NSMutableAttributedString* result = [input mutableCopy];
    for (NSDictionary* edit in edits.reverseObjectEnumerator) {
        NSRange range = [edit[@"range"] rangeValue];
        NSDictionary* attrs = [result attributesAtIndex:range.location
                                         effectiveRange:NULL];
        NSAttributedString* piece =
            [[NSAttributedString alloc] initWithString:edit[@"repl"]
                                            attributes:attrs];
        [result replaceCharactersInRange:range withAttributedString:piece];
    }
    return result;
}

// MARK: - Rename localized strings
// Every UI string routes through this Foundation method in 12.3, so the rename
// applies broadly. Skip our own bundle so the tweak's strings aren't
// reprocessed.
%hook NSBundle
- (NSString*)localizedStringForKey:(NSString*)key
                             value:(NSString*)value
                             table:(NSString*)tableName {
    NSString* result = %orig;
    if (![BHTSettings boolForKey:@"restore_twitter_names"] ||
        self == [BHTBundle sharedBundle].mainBundle) {
        return result;
    }

    NSString* override = key ? RenameKeyOverrides()[key] : nil;
    if (override) {
        return override;
    }
    return result.length > 0 ? RestoreTwitterTerminology(result) : result;
}
%end

// MARK: - Rename server-composed text
// TFNAttributedTextView renders chrome and server-composed URT text that
// carries no localization key, out of the NSBundle hook's reach. The
// TTAStatusBodyAttributedTextView subclass (tweet bodies) is skipped so a
// user's own words aren't mangled.
%hook TFNAttributedTextView
- (void)setTextModel:(TFNAttributedTextModel*)model {
    if (!model || !model.attributedString) {
        %orig(model);
        return;
    }

    NSMutableAttributedString* newString = nil;
    BOOL textChanged = NO;

    if ([BHTSettings boolForKey:@"restore_twitter_names"] &&
        ![self isKindOfClass:%c(TTAStatusBodyAttributedTextView)]) {
        NSAttributedString* source = newString ?: model.attributedString;
        NSAttributedString* renamed = RestoreTwitterAttributed(source);
        if (renamed != source) {
            newString = [renamed mutableCopy];
            textChanged = YES;
        }
    }

    if (!newString) {
        %orig(model);
        return;
    }

    if (textChanged) {
        // Text length changed, so rebuild the model to refresh length-derived
        // state.
        TFNAttributedTextModel* newModel = [[%c(TFNAttributedTextModel) alloc]
            initWithAttributedString:newString];
        %orig(newModel);
    } else if ([model respondsToSelector:@selector(setAttributedString:)]) {
        // Attributes only: keep the model to preserve its layout metadata.
        [model setAttributedString:newString];
        %orig(model);
    } else {
        TFNAttributedTextModel* newModel = [[%c(TFNAttributedTextModel) alloc]
            initWithAttributedString:newString];
        %orig(newModel);
    }
}
%end

// MARK: - Label the "new posts" refresh pill
// The facepile pill variant hardcodes blank text (no feature flag gates it).
// The tweak ships the label in the app's terminology and routes it through the
// rename pipeline, so "restore_twitter_names" converts it per-language.
static NSString* PillLabelText(void) {
    NSString* label =
        [[BHTBundle sharedBundle] localizedStringForKey:@"REFRESH_PILL_TEXT"];
    if ([BHTSettings boolForKey:@"restore_twitter_names"]) {
        label = RestoreTwitterTerminology(label);
    }
    return label;
}

%hook TUIUpdateIndicator

- (void)_recreatePillControlForContentNotification:(id)notification
                                      hideOnScroll:(BOOL)hideOnScroll {
    %orig;

    if (![BHTSettings boolForKey:@"refresh_pill_label"]) {
        return;
    }

    TFNPillControl* pill = self.pillControl;
    NSString* current = [pill.text
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if (current.length > 0) {
        return;
    }

    NSString* label = PillLabelText();
    if (label) {
        pill.text = label;
    }
}

%end
