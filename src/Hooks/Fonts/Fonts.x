#import "Fonts.h"

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

%hook UIFont

+ (UIFont*)tfn_fontWithName:(NSString*)name size:(CGFloat)size {
    UIFont* originalFont = %orig;
    BOOL isBold = [name containsString:@"Bold"] || [name containsString:@"Heavy"] ||
                  [name containsString:@"Black"] || [name containsString:@"Semibold"];
    return BHTReplaceFont(originalFont, isBold);
}

- (id)tfn_CTFont {
    // X's -[UIFont(TFNUIFontGroup) tfn_CTFont] backs named fonts with a
    // static NSCache (countLimit = 3) and returns the CTFont unretained:
    // the cache is the sole owner. Once regular AND bold custom fonts are
    // both set, a single tweet detail view creates 4+ "name-size"
    // combinations, the cache evicts an in-use CTFont, and the next
    // addAttribute: crashes in attributeDictionaryHash (#269).
    // Pin the CTFonts of the user's custom fonts for the process lifetime.
    NSString* regularName = CustomFontName(NO);
    NSString* boldName = CustomFontName(YES);
    if (!regularName && !boldName) {
        return %orig;
    }
    // The regular picker runs with includeFaces = NO, so that slot holds a
    // family name, while the bold picker stores a PostScript face name and
    // -fontName only reports the PostScript name of the resolved face. Match
    // both properties: comparing -fontName alone never recognises the regular
    // font as custom, so its CTFont keeps being evicted (#269).
    BOOL isCustom = (regularName && ([self.fontName isEqualToString:regularName] ||
                                     [self.familyName isEqualToString:regularName])) ||
                    (boldName && ([self.fontName isEqualToString:boldName] ||
                                  [self.familyName isEqualToString:boldName]));
    if (!isCustom) {
        return %orig;
    }

    static NSMutableDictionary* pinnedCTFonts = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pinnedCTFonts = [NSMutableDictionary new];
    });
    // Same "name-size" key format X's NSCache uses, so each distinct
    // combination is pinned exactly once.
    NSString* key = [NSString stringWithFormat:@"%@-%@", self.fontName, @(self.pointSize)];

    // Answer from the pinned copy without calling %orig: routing the font back
    // through X's cache could hand out (or release) a CTFont that the cache has
    // already evicted while callers still use it.
    @synchronized(pinnedCTFonts) {
        id pinned = pinnedCTFonts[key];
        if (pinned) {
            return pinned;
        }
    }

    id ctFont = %orig;
    if (!ctFont || ctFont == self) {
        return ctFont;
    }
    @synchronized(pinnedCTFonts) {
        id pinned = pinnedCTFonts[key];
        if (pinned) {
            // Another thread pinned this combination while %orig was running.
            return pinned;
        }
        // The dictionary holds the only strong reference, keeping the CTFont
        // alive after X's cache evicts it.
        pinnedCTFonts[key] = ctFont;
    }
    return ctFont;
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

%hook _TtC11XNavigation22NavigationBarTitleView

- (void)layoutSubviews {
    for (NSString* name in @[@"titleLabel", @"subtitleLabel"]) {
        id value = objectIvar(self, name.UTF8String);
        if (![value isKindOfClass:[UILabel class]]) {
            continue;
        }

        UILabel* label = value;
        UIFont* originalFont = label.font;
        UIFont* customFont =
            BHTReplaceFont(originalFont, BHTFontIsBold(originalFont));
        if (customFont != originalFont) {
            label.font = customFont;
        }
    }
    %orig;
}

%end
