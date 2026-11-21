#import "Fonts.h"

// The picked font name for a weight, or nil when the user runs Twitter's own.
NSString* CustomFontName(BOOL isBold) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"custom_fonts"]) {
        return nil;
    }
    return [defaults objectForKey:isBold ? @"bhtwitter_font_2" : @"bhtwitter_font_1"];
}

BOOL BHTFontIsBold(UIFont* font) {
    if (!font) {
        return NO;
    }
    NSString* name = font.fontName;
    NSString* selectedBold = CustomFontName(YES);
    if (selectedBold && [name isEqualToString:selectedBold]) {
        return YES;
    }
    NSString* selectedRegular = CustomFontName(NO);
    if (selectedRegular && [name isEqualToString:selectedRegular]) {
        return NO;
    }
    if ([name containsString:@"Bold"] || [name containsString:@"Heavy"] ||
        [name containsString:@"Black"] || [name containsString:@"Semibold"] ||
        [name containsString:@"SemiBold"] || [name containsString:@"Demi"]) {
        return YES;
    }
    if (font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) {
        return YES;
    }
    NSDictionary* traits = font.fontDescriptor.fontAttributes[UIFontDescriptorTraitsAttribute];
    NSNumber* weight = traits[UIFontWeightTrait];
    return weight && weight.doubleValue >= UIFontWeightSemibold;
}

UIFont* BHTReplaceFont(UIFont* originalFont, BOOL isBold) {
    NSString* customName = CustomFontName(isBold);
    if (!customName || !originalFont || [originalFont.fontName isEqualToString:customName]) {
        return originalFont;
    }
    return [UIFont fontWithName:customName size:originalFont.pointSize] ?: originalFont;
}

UIBarButtonItemAppearance* BHTBarButtonAppearanceWithFont(
    UIBarButtonItemAppearance* originalAppearance, NSString* fontName) {
    if (!originalAppearance || !fontName) {
        return originalAppearance;
    }

    UIBarButtonItemAppearance* appearance = [originalAppearance copy];
    for (UIBarButtonItemStateAppearance* state in
         @[appearance.normal, appearance.highlighted, appearance.disabled, appearance.focused]) {
        NSMutableDictionary* attributes =
            [state.titleTextAttributes mutableCopy] ?: [NSMutableDictionary dictionary];
        UIFont* existingFont = attributes[NSFontAttributeName];
        UIFont* customFont = [UIFont fontWithName:fontName
                                             size:existingFont ? existingFont.pointSize : 17.0];
        if (customFont) {
            attributes[NSFontAttributeName] = customFont;
            state.titleTextAttributes = attributes;
        }
    }
    return appearance;
}

UINavigationBarAppearance* BHTNavigationAppearanceWithFonts(
    UINavigationBarAppearance* originalAppearance) {
    if (!originalAppearance) {
        return nil;
    }

    NSString* boldName = CustomFontName(YES);
    NSString* regularName = CustomFontName(NO);
    if (!boldName && !regularName) {
        return originalAppearance;
    }

    UINavigationBarAppearance* appearance = [originalAppearance copy];
    if (boldName) {
        NSMutableDictionary* attributes =
            [appearance.titleTextAttributes mutableCopy] ?: [NSMutableDictionary dictionary];
        UIFont* existingFont = attributes[NSFontAttributeName];
        UIFont* customFont = [UIFont fontWithName:boldName
                                             size:existingFont ? existingFont.pointSize : 17.0];
        if (customFont) {
            attributes[NSFontAttributeName] = customFont;
            appearance.titleTextAttributes = attributes;
        }
        appearance.doneButtonAppearance =
            BHTBarButtonAppearanceWithFont(appearance.doneButtonAppearance, boldName);
    }
    if (regularName) {
        appearance.buttonAppearance =
            BHTBarButtonAppearanceWithFont(appearance.buttonAppearance, regularName);
        appearance.backButtonAppearance =
            BHTBarButtonAppearanceWithFont(appearance.backButtonAppearance, regularName);
    }
    return appearance;
}
