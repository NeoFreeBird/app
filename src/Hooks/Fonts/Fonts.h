#import "../HookHelpers.h"

NSString* CustomFontName(BOOL isBold);
BOOL BHTFontIsBold(UIFont* font);
UIFont* BHTReplaceFont(UIFont* originalFont, BOOL isBold);
UIBarButtonItemAppearance* BHTBarButtonAppearanceWithFont(
    UIBarButtonItemAppearance* originalAppearance, NSString* fontName);
UINavigationBarAppearance* BHTNavigationAppearanceWithFonts(
    UINavigationBarAppearance* originalAppearance);
