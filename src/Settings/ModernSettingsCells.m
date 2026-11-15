//
//  ModernSettingsCells.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/ModernSettingsCells.h"
#import "Core/BHTManager.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/Palette.h"

// Copied values from the main settings, yeah I'm lazy.
static const CGFloat ListRowInset = 24;
static const CGFloat ListRowGlyphSize = 24;
static const CGFloat ListRowTextGap = 16;
static const CGFloat ListRowPadding = 10;
static const CGFloat ListRowSpacing = 8;

@interface ModernSettingsTableViewCell ()
@property (nonatomic, strong) UIStackView* textStack;
@property (nonatomic, strong) NSLayoutConstraint* textLeadingToIcon;
@property (nonatomic, strong) NSLayoutConstraint* textLeadingToEdge;
@property (nonatomic, strong) NSLayoutConstraint* textBottom;
@end

@implementation ModernSettingsTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupViews];
        [self setupConstraints];
    }
    return self;
}

- (void)setupViews {
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.iconImageView];

    id fontGroup = [BHTManager sharedFontGroup];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyFont)];
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.numberOfLines = 2;

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    self.subtitleLabel.numberOfLines = 0;
    [self updateSubtitleColor];

    self.textStack =
        [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subtitleLabel]];
    self.textStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.textStack.axis = UILayoutConstraintAxisVertical;
    self.textStack.spacing = 4;
    [self.contentView addSubview:self.textStack];

    self.chevronImageView = [[UIImageView alloc] init];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.chevronImageView];

    self.backgroundColor = [Palette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (void)setupConstraints {
    UIView* content = self.contentView;

    self.textLeadingToIcon =
        [self.textStack.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor
                                                     constant:ListRowTextGap];
    self.textLeadingToEdge = [self.textStack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                                                          constant:ListRowInset];
    self.textBottom = [self.textStack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor
                                                                  constant:-ListRowPadding];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconImageView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                                         constant:ListRowInset],
        [self.iconImageView.topAnchor constraintEqualToAnchor:content.topAnchor
                                                     constant:ListRowPadding],
        [self.iconImageView.widthAnchor constraintEqualToConstant:ListRowGlyphSize],
        [self.iconImageView.heightAnchor constraintEqualToConstant:ListRowGlyphSize],

        self.textLeadingToIcon,
        [self.textStack.topAnchor constraintEqualToAnchor:content.topAnchor
                                                 constant:ListRowPadding],
        [self.textStack.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor
                                                      constant:-ListRowTextGap],
        self.textBottom,
        // Keeps a single-line row as tall as its icon.
        [self.textStack.heightAnchor constraintGreaterThanOrEqualToConstant:ListRowGlyphSize],

        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                                             constant:-ListRowInset],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.textStack.centerYAnchor],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:ListRowGlyphSize],
        [self.chevronImageView.heightAnchor constraintEqualToConstant:ListRowGlyphSize]
    ]];
}

- (void)setLastInSection:(BOOL)lastInSection {
    _lastInSection = lastInSection;
    self.textBottom.constant = -(ListRowPadding + (lastInSection ? 0 : ListRowSpacing));
}

- (void)configureWithTitle:(NSString*)title
                  subtitle:(NSString*)subtitle
                  iconName:(NSString*)iconName {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = subtitle.length == 0;

    // Rows without an icon pull their text to the inset, as X's leading .none does.
    BOOL hasIcon = iconName.length > 0;
    self.iconImageView.hidden = !hasIcon;
    self.textLeadingToIcon.active = hasIcon;
    self.textLeadingToEdge.active = !hasIcon;

    objc_setAssociatedObject(self, @selector(iconName), iconName, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self updateIconColors];
}

// Vector images bake in their fill color, so they are re-rendered on every theme change.
- (void)updateIconColors {
    UIColor* glyphColor = [[UIColor labelColor] resolvedColorWithTraitCollection:self.traitCollection];
    CGSize glyphSize = CGSizeMake(ListRowGlyphSize, ListRowGlyphSize);

    NSString* iconName = objc_getAssociatedObject(self, @selector(iconName));
    self.iconImageView.image =
        iconName ? [UIImage tfn_vectorImageNamed:iconName fitsSize:glyphSize fillColor:glyphColor]
                 : nil;
    self.chevronImageView.image = [UIImage tfn_vectorImageNamed:@"chevron_right"
                                                       fitsSize:glyphSize
                                                      fillColor:glyphColor];
}

// X tints secondary row text as the primary label colour at 60% opacity.
- (void)updateSubtitleColor {
    self.subtitleLabel.textColor = [[UIColor labelColor] colorWithAlphaComponent:0.6];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [Palette currentBackgroundColor];
    [self updateIconColors];
    if (previousTraitCollection.preferredContentSizeCategory !=
        self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [BHTManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyFont)];
        self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    }
}

@end

@implementation ModernSettingsSimpleButtonCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupViews];
        [self setupConstraints];
    }
    return self;
}

- (void)setupViews {
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.titleLabel];

    self.chevronImageView = [[UIImageView alloc] init];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.chevronImageView];

    self.backgroundColor = [Palette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    [self updateChevronColor];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                      constant:20],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor
                                                       constant:-16],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                  constant:16],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                     constant:-16],

        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                             constant:-20],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:18],
        [self.chevronImageView.heightAnchor constraintEqualToConstant:18]
    ]];
}

- (void)configureWithTitle:(NSString*)title {
    self.titleLabel.text = title;
}

- (void)updateChevronColor {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor* chevronColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.chevronImageView.image = [UIImage tfn_vectorImageNamed:@"chevron_right"
                                                       fitsSize:CGSizeMake(18, 18)
                                                      fillColor:chevronColor];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [Palette currentBackgroundColor];
    [self updateChevronColor];
    if (previousTraitCollection.preferredContentSizeCategory !=
        self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [BHTManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    }
}

@end

@implementation ModernSettingsCompactButtonCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupViews];
        [self setupConstraints];
    }
    return self;
}

- (void)setupViews {
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.contentView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    self.subtitleLabel.textAlignment = NSTextAlignmentRight;
    [self updateSubtitleColor];
    [self.contentView addSubview:self.subtitleLabel];

    self.chevronImageView = [[UIImageView alloc] init];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.chevronImageView];

    self.backgroundColor = [Palette currentBackgroundColor];
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    [self updateChevronColor];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                      constant:20],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                  constant:16],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                     constant:-16],

        [self.subtitleLabel.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:self.titleLabel.trailingAnchor
                                        constant:16],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor
                                                          constant:-8],
        [self.subtitleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                             constant:-20],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:18],
        [self.chevronImageView.heightAnchor constraintEqualToConstant:18]
    ]];
    [self.titleLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh
                                       forAxis:UILayoutConstraintAxisHorizontal];
    [self.subtitleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow
                                          forAxis:UILayoutConstraintAxisHorizontal];
    [self.subtitleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                        forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}

- (void)updateChevronColor {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor* chevronColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.chevronImageView.image = [UIImage tfn_vectorImageNamed:@"chevron_right"
                                                       fitsSize:CGSizeMake(18, 18)
                                                      fillColor:chevronColor];
}

- (void)updateSubtitleColor {
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id currentPalette = [settings currentColorPalette];
    id colorPalette = [currentPalette colorPalette];
    UIColor* subtitleColor = [colorPalette performSelector:@selector(tabBarItemColor)];
    self.subtitleLabel.textColor = subtitleColor;
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.backgroundColor = [Palette currentBackgroundColor];
    [self updateChevronColor];
    [self updateSubtitleColor];
    if (previousTraitCollection.preferredContentSizeCategory !=
        self.traitCollection.preferredContentSizeCategory) {
        id fontGroup = [BHTManager sharedFontGroup];
        self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
        self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    }
}

@end

@implementation ModernSettingsToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [Palette currentBackgroundColor];
        self.titleLabel = [UILabel new];
        self.titleLabel.numberOfLines = 2;
        self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.titleLabel];
        self.subtitleLabel = [UILabel new];
        self.subtitleLabel.numberOfLines = 0;
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.subtitleLabel];
        self.toggleSwitch = [UISwitch new];
        self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.toggleSwitch];
        [self applyTheme];
        [NSLayoutConstraint activateConstraints:@[
            [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                             constant:-20],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                          constant:20],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                      constant:14],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor
                                                           constant:-16],
            [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor
                                                         constant:4],
            [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                            constant:-14]
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString*)title subtitle:(NSString*)subtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}

- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events {
    [self.toggleSwitch addTarget:target action:action forControlEvents:events];
}

- (void)applyTheme {
    id fontGroup = [BHTManager sharedFontGroup];
    self.titleLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    self.subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    Class TAEColorSettingsCls = objc_getClass("TAEColorSettings");
    id settings = [TAEColorSettingsCls sharedSettings];
    id colorPalette = [[settings currentColorPalette] colorPalette];
    self.titleLabel.textColor = [colorPalette performSelector:@selector(textColor)];
    self.subtitleLabel.textColor = [colorPalette performSelector:@selector(tabBarItemColor)];
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
}

@end
