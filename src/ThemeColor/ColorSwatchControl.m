//
//  ColorSwatchControl.m
//  NeoFreeBird
//

#import "ColorSwatchControl.h"

// Native swatch: 36pt circle, 2pt selection ring at the edge.
static const CGFloat kSwatchDiameter = 36.0;
static const CGFloat kSelectionRingWidth = 2.0;

@interface ColorSwatchControl ()
@property (nonatomic, strong) UIView* circleView;
@end

@implementation ColorSwatchControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.circleView = [[UIView alloc] init];
        self.circleView.translatesAutoresizingMaskIntoConstraints = NO;
        self.circleView.userInteractionEnabled = NO;
        self.circleView.layer.cornerRadius = kSwatchDiameter / 2.0;
        self.circleView.clipsToBounds = YES;
        [self addSubview:self.circleView];

        [NSLayoutConstraint activateConstraints:@[
            [self.circleView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.circleView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.circleView.widthAnchor constraintEqualToConstant:kSwatchDiameter],
            [self.circleView.heightAnchor constraintEqualToConstant:kSwatchDiameter]
        ]];
    }
    return self;
}

- (void)setSwatchColor:(UIColor*)color {
    self.circleView.backgroundColor = color;
}

- (void)setSwatchSelected:(BOOL)selected {
    // The native ring sits at the circle's edge in a contrasting colour.
    self.circleView.layer.borderWidth = selected ? kSelectionRingWidth : 0.0;
    self.circleView.layer.borderColor = selected ? [UIColor labelColor].CGColor : nil;
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // Keep the ring colour resolved for the current light/dark appearance.
    if (self.circleView.layer.borderWidth > 0) {
        self.circleView.layer.borderColor = [UIColor labelColor].CGColor;
    }
}

@end
