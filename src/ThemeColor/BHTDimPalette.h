//
//  BHTDimPalette.h
//  NeoFreeBird
//
//  Created by orionblur
//

#import <UIKit/UIKit.h>

/**
 * Returns YES if the Dim theme is enabled, NO otherwise.
 */
BOOL BHTDimThemeEnabled(void);

/**
 * The three Dim shades, for direct use where a caller isn't going through the
 * palette proxy below (e.g. overriding UIKit's own dynamic system colors,
 * which are a separate source of "pure black" chrome the TAEColorPalette
 * proxy never sees).
 */
UIColor* BHTDimBackgroundColor(void);
UIColor* BHTDimElevatedBackgroundColor(void);
UIColor* BHTDimHighlightBackgroundColor(void);
UIColor* BHTDimSearchPillColor(void);

/**
 * Which of the three Dim shades a resolved, opaque color is, if any. Compared
 * against the same constants the shade constructors above use.
 */
typedef NS_ENUM(NSInteger, BHTDimShadeKind) {
    BHTDimShadeNone,
    BHTDimShadeBackground,
    BHTDimShadeElevated,
    BHTDimShadeHighlight,
};

BHTDimShadeKind BHTDimShadeOfColor(UIColor* _Nullable color);

/**
 * Best-effort remap for a color that's already been resolved for a trait
 * collection (i.e. flattened to concrete RGBA), used to catch UIKit's
 * private dynamic-color classes (UIDynamicSystemColor, UIDynamicCatalogColor)
 * which never go through TAEColorPalette or the named UIColor class methods.
 * Only touches colors that look like opaque, achromatic background chrome
 * (near-black grays); returns nil -- meaning "leave it alone" -- for
 * anything with real hue, transparency, or brightness outside that band, so
 * text, accents, and translucent overlays are never touched.
 */
UIColor* _Nullable BHTDimReplacementForResolvedColor(UIColor* resolved);

/**
 * Self-contained "is this white/near-white" check, used to keep genuinely
 * white chrome from being force-overwritten by the blanket TFNSolidColorView
 * recolor in Theme.x (that override doesn't go through
 * BHTDimReplacementForResolvedColor's heuristic at all, so it needs its own
 * guard). Deliberately not relying on UIColor's private safari_isCloseToWhite
 * category -- undocumented, and it didn't produce reliable results here.
 */
BOOL BHTColorIsCloseToWhite(UIColor* _Nullable color);

/**
 * Returns dim carrying source's dynamic color identifier, if it has one.
 * TFNDynamicColorManager uses that identifier to reload a color from the new
 * palette on an appearance change, so an untagged Dim color would stay navy.
 */
UIColor* BHTDimColorPreservingIdentifier(UIColor* dim, UIColor* _Nullable source);

/**
 * Wraps a live TAEColorPalette-conforming object, substituting Dim's navy
 * background family for the handful of properties it overrides and
 * forwarding everything else (text, links, accents, dividers) untouched to
 * the wrapped palette.
 *
 * The app only ever renders Light or Dark now -- there's no native third
 * state -- so this is how Dim comes back: it recolors Dark rather than
 * adding an option alongside it.
 */
@interface BHTDimPaletteProxy : NSProxy

+ (instancetype)proxyWithPalette:(id)palette;

@end
