//
//  Branding.x
//  NeoFreeBird
//

#import "Core/BHTTerminology.h"
#import "HookHelpers.h"

// MARK: - Restore Twitter terminology
// Three layers, driven by locale files in the tweak bundle:
//   1. RenameOverrides.strings — Twitter localization key -> exact replacement,
//      a missing key falls through to the generic replacement
//   2. RenamePhrases.strings — exact source text -> complete translated phrase.
//   3. RenameWords.strings — generic word replacements ("X" -> "Twitter",
//      "Post" -> "Tweet", etc.) applied to localized and server-side strings

// Foundation may localize an error while loading a table. Do not recursively
// enter the dispatch_once initializers on the same thread.
static __thread BOOL handlingTerminologyLocalization = NO;

static NSDictionary<NSString*, NSString*>* RenameTable(NSString* name) {
    BOOL wasHandlingLocalization = handlingTerminologyLocalization;
    handlingTerminologyLocalization = YES;
    @try {
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
            [[appLanguage stringByReplacingOccurrencesOfString:@"_" withString:@"-"]
                componentsSeparatedByString:@"-"]
                .firstObject;
        NSString* lprojCode =
            [[localization stringByReplacingOccurrencesOfString:@"_" withString:@"-"]
                componentsSeparatedByString:@"-"]
                .firstObject;
        if (![appCode isEqualToString:lprojCode]) {
            return @{};
        }

        // Read the selected directory directly: NSBundle resource lookup can fall
        // back to another language when this particular table is missing.
        NSString* directory = [bundle.bundlePath stringByAppendingPathComponent:
                                                     [localization stringByAppendingPathExtension:@"lproj"]];
        NSString* path = [directory stringByAppendingPathComponent:
                                        [name stringByAppendingPathExtension:@"strings"]];
        return BHTLoadTerminologyTable(path);
    } @finally {
        handlingTerminologyLocalization = wasHandlingLocalization;
    }
}

static NSDictionary<NSString*, NSString*>* RenameKeyOverrides(void) {
    static NSDictionary* overrides = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        overrides = RenameTable(@"RenameOverrides");
    });
    return overrides;
}

static NSArray<NSDictionary*>* RenameEdits(NSString* input) {
    static BHTTerminology* terminology = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* language = [NSBundle mainBundle].preferredLocalizations.firstObject ?: @"en";
        terminology = [[BHTTerminology alloc] initWithWords:RenameTable(@"RenameWords")
                                                    phrases:RenameTable(@"RenamePhrases")
                                                     locale:[NSLocale localeWithLocaleIdentifier:language]];
    });
    return [terminology editsForString:input];
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
    if (handlingTerminologyLocalization) {
        return %orig;
    }
    handlingTerminologyLocalization = YES;
    @try {
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
    } @finally {
        handlingTerminologyLocalization = NO;
    }
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
