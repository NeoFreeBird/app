#import "Branding.h"

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
