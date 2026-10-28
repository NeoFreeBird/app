//
//  Fonts.x
//  NeoFreeBird
//

#import "Headers/XHeaders.h"
#import "HookHelpers.h"

// MARK: - Change font

%hook UIFontPickerViewController
- (void)viewWillAppear:(BOOL)arg1 {
    %orig(arg1);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[[BHTBundle sharedBundle]
                          localizedStringForKey:@"CUSTOM_FONTS_NAVIGATION_BUTTON_TITLE"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(customFontsHandler)];
}
%new
- (void)customFontsHandler {
    if ([[NSFileManager defaultManager]
            fileExistsAtPath:@"/var/mobile/Library/Fonts/AddedFontCache.plist"]) {
        NSAttributedString* AttString = [[NSAttributedString alloc]
            initWithString:[[BHTBundle sharedBundle] localizedStringForKey:@"CUSTOM_FONTS_MENU_TITLE"]
                attributes:@{
                    NSFontAttributeName: [BHTManager menuTitleFont],
                    NSForegroundColorAttributeName: UIColor.labelColor
                }];
        TFNActiveTextItem* title =
            [[%c(TFNActiveTextItem) alloc] initWithTextModel:[[%c(TFNAttributedTextModel) alloc]
                                                                     initWithAttributedString:AttString]
                                                    activeRanges:nil];

        NSMutableArray* actions = [[NSMutableArray alloc] init];
        [actions addObject:title];

        NSDictionary* plistDictionary = [NSPropertyListSerialization
            propertyListWithData:
                [NSData dataWithContentsOfURL:
                            [NSURL fileURLWithPath:@"/var/mobile/Library/Fonts/AddedFontCache.plist"]]
                         options:NSPropertyListImmutable
                          format:NULL
                           error:nil];
        [plistDictionary enumerateKeysAndObjectsUsingBlock:^(id _Nonnull key, id _Nonnull obj,
                                                             BOOL* _Nonnull stop) {
            @try {
                NSString* fontName = ((NSArray*)[obj valueForKey:@"psNames"]).firstObject;
                TFNActionItem* fontAction = [%c(TFNActionItem)
                    actionItemWithTitle:fontName
                                 action:^{
                                     if (self.configuration.includeFaces) {
                                         [self setSelectedFontDescriptor:[UIFontDescriptor
                                                                             fontDescriptorWithFontAttributes:@{
                                                                                 UIFontDescriptorNameAttribute:
                                                                                     fontName
                                                                             }]];
                                     } else {
                                         [self setSelectedFontDescriptor:[UIFontDescriptor
                                                                             fontDescriptorWithFontAttributes:@{
                                                                                 UIFontDescriptorFamilyAttribute:
                                                                                     fontName
                                                                             }]];
                                     }
                                     [self.delegate fontPickerViewControllerDidPickFont:self];
                                 }];
                [actions addObject:fontAction];
            } @catch (NSException* exception) {
                NSLog(@"Unable to find installed fonts /n reason: %@", exception.reason);
            }
        }];

        TFNMenuSheetViewController* alert = [[%c(TFNMenuSheetViewController) alloc]
            initWithActionItems:[NSArray arrayWithArray:actions]];
        [alert tfnPresentedCustomPresentFromViewController:self animated:YES completion:nil];
    } else {
        UIAlertController* errAlert = [UIAlertController
            alertControllerWithTitle:@"BHTwitter"
                             message:[[BHTBundle sharedBundle]
                                         localizedStringForKey:@"CUSTOM_FONTS_TUT_ALERT_MESSAGE"]
                      preferredStyle:UIAlertControllerStyleAlert];

        [errAlert
            addAction:
                [UIAlertAction
                    actionWithTitle:[[BHTBundle sharedBundle]
                                        localizedStringForKey:@"INSTALL_IFONT_BUTTON_TITLE"]
                              style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction* _Nonnull action) {
                                [[UIApplication sharedApplication]
                                              openURL:[NSURL
                                                          URLWithString:
                                                              @"https://apps.apple.com/sa/app/"
                                                              @"ifont-find-install-any-font/id1173222289"]
                                              options:@{}
                                    completionHandler:nil];
                            }]];
        [errAlert addAction:[UIAlertAction
                                actionWithTitle:[[BHTBundle sharedBundle]
                                                    localizedTwitterStringForKey:@"OK_ACTION_LABEL"]
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
        [self presentViewController:errAlert animated:true completion:nil];
    }
}
%end

// The picked font name for a weight, or nil when the user runs Twitter's own.
static NSString* CustomFontName(BOOL isBold) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"custom_fonts"]) {
        return nil;
    }
    return [defaults objectForKey:isBold ? @"bhtwitter_font_2" : @"bhtwitter_font_1"];
}

static BOOL BHTFontIsBold(UIFont* font) {
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

static UIFont* BHTReplaceFont(UIFont* originalFont, BOOL isBold) {
    NSString* customName = CustomFontName(isBold);
    if (!customName || !originalFont || [originalFont.fontName isEqualToString:customName]) {
        return originalFont;
    }
    return [UIFont fontWithName:customName size:originalFont.pointSize] ?: originalFont;
}

%hook UIFont

+ (UIFont*)tfn_fontWithName:(NSString*)name size:(CGFloat)size {
    UIFont* originalFont = %orig;
    BOOL isBold = [name containsString:@"Bold"] || [name containsString:@"Heavy"] ||
                  [name containsString:@"Black"] || [name containsString:@"Semibold"];
    return BHTReplaceFont(originalFont, isBold);
}

%end

// XDSFoundation.Fonts wraps the result of +fontForToken: as a SwiftUI.Font.
// This catalog hook therefore covers its SwiftUI token getters as well.
%hook XFontCatalog

+ (UIFont*)fontForToken:(NSInteger)token {
    UIFont* originalFont = %orig;
    return BHTReplaceFont(originalFont, BHTFontIsBold(originalFont));
}

+ (UIFont*)customFontOfSize:(CGFloat)size weight:(NSInteger)weight
    scalesWithDynamicType:(BOOL)scales {
    UIFont* originalFont = %orig;
    return BHTReplaceFont(originalFont, weight >= 2);
}

+ (UIFont*)contentFontWithOffset:(CGFloat)offset weight:(NSInteger)weight {
    UIFont* originalFont = %orig;
    return BHTReplaceFont(originalFont, weight >= 2);
}

+ (UIFont*)tabularDigitsFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont* originalFont = %orig;
    UIFont* customFont = BHTReplaceFont(originalFont, weight >= UIFontWeightSemibold);
    return customFont == originalFont ? originalFont
                                     : ([customFont tfn_withMonospacedDigits] ?: customFont);
}

%end

%hook XDSButtonContentElement

+ (id)labelWithText:(id)text font:(id)font color:(id)color {
    if (![font isKindOfClass:[UIFont class]]) {
        return %orig;
    }
    UIFont* customFont = BHTReplaceFont((UIFont*)font, BHTFontIsBold((UIFont*)font));
    return %orig(text, customFont, color);
}

%end

static UIBarButtonItemAppearance* BHTBarButtonAppearanceWithFont(
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

static UINavigationBarAppearance* BHTNavigationAppearanceWithFonts(
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

%hook XNAVNavigationController

- (void)viewDidLoad {
    %orig;

    UINavigationBar* navigationBar = self.navigationBar;
    navigationBar.standardAppearance =
        BHTNavigationAppearanceWithFonts(navigationBar.standardAppearance);
    if (navigationBar.scrollEdgeAppearance) {
        navigationBar.scrollEdgeAppearance =
            BHTNavigationAppearanceWithFonts(navigationBar.scrollEdgeAppearance);
    }
    if (navigationBar.compactAppearance) {
        navigationBar.compactAppearance =
            BHTNavigationAppearanceWithFonts(navigationBar.compactAppearance);
    }
    if (@available(iOS 15.0, *)) {
        if (navigationBar.compactScrollEdgeAppearance) {
            navigationBar.compactScrollEdgeAppearance =
                BHTNavigationAppearanceWithFonts(navigationBar.compactScrollEdgeAppearance);
        }
    }
}

%end
