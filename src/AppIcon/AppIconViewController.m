//
//  AppIconViewController.m
//  NeoFreeBird
//
//  Created by Bandar Alruwaili on 10/12/2023.
//  Modified by actuallyaridan on 25/05/2025.
//

#import "AppIconViewController.h"
#import <UIKit/UIKit.h>
#import "AppIconCell.h"
#import "AppIconItem.h"
#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import "ThemeColor/Palette.h"

extern UIColor* CurrentAccentColor(void);

// UIApplication's alternateIconName getter goes stale on sideloaded installs
// (setting the icon works, but the getter keeps reporting an old name across
// reinstalls), so the last choice made here is what the radios trust.
static NSString* const kLastSelectedIconKey = @"bh_last_selected_app_icon";
static NSString* const kPrimaryIconSentinel = @"PrimaryIcon";

@interface UIColor (NativeTokens_AppIconVC)
+ (id)tfnuiColors;
@end

@interface NSObject (NativeTokens_AppIconVC)
- (UIColor*)textDetailsColor;
@end

static UIColor* AppIconDetailTextColor(void) {
    id colors = [UIColor respondsToSelector:@selector(tfnuiColors)]
                    ? [UIColor tfnuiColors]
                    : nil;
    if (colors && [colors respondsToSelector:@selector(textDetailsColor)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIColor* details = [colors performSelector:@selector(textDetailsColor)];
#pragma clang diagnostic pop
        if ([details isKindOfClass:[UIColor class]]) {
            return details;
        }
    }
    return [UIColor secondaryLabelColor];
}

static UIFont* AppIconDetailFont(void) {
    return [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15];
}

static NSString* AppIconDetailText(void) {
    return [[BHTBundle sharedBundle]
        localizedStringForKey:@"SUBSCRIPTION_APP_ICON_SETTINGS_DETAIL"];
}

@interface AppIconViewController () <UICollectionViewDelegate,
                                     UICollectionViewDataSource,
                                     UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView* appIconCollectionView;
@property (nonatomic, copy) NSArray<AppIconItem*>* icons;
@property (nonatomic, strong) NSCache<AppIconItem*, UIImage*>* thumbnailCache;
@property (nonatomic, strong) UIView* loadingView;
@property (nonatomic, strong) UIActivityIndicatorView* loadingIndicator;
@end

@implementation AppIconViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.title = [[BHTBundle sharedBundle]
        localizedStringForKey:@"SUBSCRIPTION_APP_ICON_SETTINGS_TITLE"];

    UICollectionViewFlowLayout* flow = [UICollectionViewFlowLayout new];
    flow.sectionInset = UIEdgeInsetsMake(16, 16, 16, 16);
    flow.minimumLineSpacing = 10;
    flow.minimumInteritemSpacing = 10;

    self.appIconCollectionView =
        [[UICollectionView alloc] initWithFrame:CGRectZero
                           collectionViewLayout:flow];
    [self.appIconCollectionView registerClass:[AppIconCell class]
                   forCellWithReuseIdentifier:[AppIconCell reuseIdentifier]];
    [self.appIconCollectionView registerClass:[UICollectionReusableView class]
                   forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                          withReuseIdentifier:@"HeaderView"];
    self.appIconCollectionView.delegate = self;
    self.appIconCollectionView.dataSource = self;
    self.appIconCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.appIconCollectionView.backgroundColor = [Palette currentBackgroundColor];
    self.thumbnailCache = [NSCache new];

    self.view.backgroundColor = [Palette currentBackgroundColor];

    [self.view addSubview:self.appIconCollectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.appIconCollectionView.topAnchor
            constraintEqualToAnchor:self.view.topAnchor],
        [self.appIconCollectionView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.appIconCollectionView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.appIconCollectionView.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.loadingView = [UIView new];
    self.loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingView.backgroundColor = self.view.backgroundColor;
    [self.view addSubview:self.loadingView];

    self.loadingIndicator =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
                                             UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.accessibilityLabel = @"Loading app icons";
    [self.loadingView addSubview:self.loadingIndicator];

    [NSLayoutConstraint activateConstraints:@[
        [self.loadingView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.loadingView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.loadingView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.loadingView.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor],
        [self.loadingIndicator.centerXAnchor
            constraintEqualToAnchor:self.loadingView.centerXAnchor],
        [self.loadingIndicator.centerYAnchor
            constraintEqualToAnchor:self.loadingView.centerYAnchor],
    ]];
    [self.loadingIndicator startAnimating];

    [self loadAppIcons];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.appIconCollectionView.backgroundColor = [Palette currentBackgroundColor];
    [self.appIconCollectionView reloadData];
}

#pragma mark - Icon data

- (void)loadAppIcons {
    UITraitCollection* traitCollection = self.traitCollection;
    __weak AppIconViewController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        AppIconViewController* strongSelf = weakSelf;
        if (!strongSelf)
            return;

        NSDictionary* iconsDict =
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIcons"];
        NSMutableArray<AppIconItem*>* items = [NSMutableArray new];

        NSDictionary* primary = iconsDict[@"CFBundlePrimaryIcon"];
        if ([primary isKindOfClass:[NSDictionary class]]) {
            AppIconItem* item = [[AppIconItem alloc]
                initWithBundleIconName:primary[@"CFBundleIconName"]
                         iconFileNames:primary[@"CFBundleIconFiles"]
                         isPrimaryIcon:YES];
            if ([strongSelf thumbnailForItem:item
                             traitCollection:traitCollection]) {
                [items addObject:item];
            }
        }

        NSDictionary* alternates = iconsDict[@"CFBundleAlternateIcons"];
        if ([alternates isKindOfClass:[NSDictionary class]]) {
            NSArray<NSString*>* sortedKeys = [alternates.allKeys
                sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
            for (NSString* key in sortedKeys) {
                NSDictionary* alt = alternates[key];
                NSString* name = alt[@"CFBundleIconName"] ?: key;
                AppIconItem* item = [[AppIconItem alloc]
                    initWithBundleIconName:name
                             iconFileNames:alt[@"CFBundleIconFiles"]
                             isPrimaryIcon:NO];
                if ([strongSelf thumbnailForItem:item
                                 traitCollection:traitCollection]) {
                    [items addObject:item];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            AppIconViewController* currentSelf = weakSelf;
            if (!currentSelf)
                return;
            currentSelf.icons = items;
            [currentSelf.loadingIndicator stopAnimating];
            currentSelf.loadingView.hidden = YES;
            [currentSelf.appIconCollectionView reloadData];
        });
    });
}

- (UIImage*)thumbnailForItem:(AppIconItem*)item {
    return [self thumbnailForItem:item traitCollection:self.traitCollection];
}

- (UIImage*)thumbnailForItem:(AppIconItem*)item
             traitCollection:(UITraitCollection*)traitCollection {
    UIImage* cachedImage = [self.thumbnailCache objectForKey:item];
    if (cachedImage)
        return cachedImage;

    NSBundle* bundle = [NSBundle mainBundle];

    NSString* settingsName;
    if (item.isPrimaryIcon) {
        NSString* base = item.bundleIconName;
        if ([base hasSuffix:@"AppIcon"]) {
            base = [base substringToIndex:base.length - @"AppIcon".length];
        }
        settingsName = [NSString stringWithFormat:@"Icon-%@-settings", base];
    } else {
        settingsName = [item.bundleIconName stringByAppendingString:@"-settings"];
    }

    UIImage* img = [UIImage imageNamed:settingsName
                              inBundle:bundle
         compatibleWithTraitCollection:traitCollection];
    if (!img && item.bundleIconName) {
        img = [UIImage imageNamed:item.bundleIconName
                                 inBundle:bundle
            compatibleWithTraitCollection:traitCollection];
    }
    if (!img) {
        for (NSString* file in [item.bundleIconFiles reverseObjectEnumerator]) {
            img = [UIImage imageNamed:file
                                     inBundle:bundle
                compatibleWithTraitCollection:traitCollection];
            if (img)
                break;
        }
    }
    if (img)
        [self.thumbnailCache setObject:img forKey:item];
    return img;
}

- (BOOL)isItemActive:(AppIconItem*)item {
    NSString* saved = [[NSUserDefaults standardUserDefaults]
        stringForKey:kLastSelectedIconKey];
    NSString* current =
        saved ?: [UIApplication sharedApplication].alternateIconName;

    if (item.isPrimaryIcon) {
        return current == nil || [current isEqualToString:kPrimaryIconSentinel];
    }
    return [current isEqualToString:item.bundleIconName];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView*)cv {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView*)cv
     numberOfItemsInSection:(NSInteger)section {
    return self.icons.count;
}

- (UICollectionViewCell*)collectionView:(UICollectionView*)cv
                 cellForItemAtIndexPath:(NSIndexPath*)ip {
    AppIconCell* cell =
        [cv dequeueReusableCellWithReuseIdentifier:[AppIconCell reuseIdentifier]
                                      forIndexPath:ip];
    AppIconItem* item = self.icons[ip.row];

    [cell configureWithImage:[self thumbnailForItem:item]
                      active:[self isItemActive:item]
                 accentColor:CurrentAccentColor()];

    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView*)cv
    didSelectItemAtIndexPath:(NSIndexPath*)ip {
    if (![UIApplication sharedApplication].supportsAlternateIcons)
        return;

    AppIconItem* item = self.icons[ip.row];
    if ([self isItemActive:item])
        return;

    NSString* toSet = item.isPrimaryIcon ? nil : item.bundleIconName;

    [[NSUserDefaults standardUserDefaults]
        setObject:(toSet ?: kPrimaryIconSentinel)
           forKey:kLastSelectedIconKey];
    [cv reloadData];

    // A block is always passed: nil name + nil handler crashes UIKit.
    [[UIApplication sharedApplication] setAlternateIconName:toSet
                                          completionHandler:^(NSError* _Nullable error){}];
}

#pragma mark - Section header

- (UICollectionReusableView*)collectionView:(UICollectionView*)cv
          viewForSupplementaryElementOfKind:(NSString*)kind
                                atIndexPath:(NSIndexPath*)ip {
    UICollectionReusableView* header =
        [cv dequeueReusableSupplementaryViewOfKind:kind
                               withReuseIdentifier:@"HeaderView"
                                      forIndexPath:ip];
    [header.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.font = AppIconDetailFont();
    detail.textColor = AppIconDetailTextColor();
    detail.numberOfLines = 0;
    detail.textAlignment = NSTextAlignmentLeft;
    detail.text = AppIconDetailText();
    [header addSubview:detail];

    [NSLayoutConstraint activateConstraints:@[
        [detail.leadingAnchor constraintEqualToAnchor:header.leadingAnchor
                                             constant:16],
        [detail.trailingAnchor constraintEqualToAnchor:header.trailingAnchor
                                              constant:-16],
        [detail.topAnchor constraintEqualToAnchor:header.topAnchor
                                         constant:16],
        [detail.bottomAnchor constraintEqualToAnchor:header.bottomAnchor
                                            constant:-16]
    ]];

    return header;
}

- (CGSize)collectionView:(UICollectionView*)cv
                             layout:(UICollectionViewLayout*)layout
    referenceSizeForHeaderInSection:(NSInteger)section {
    CGFloat width = CGRectGetWidth(cv.bounds);
    CGRect textRect = [AppIconDetailText()
        boundingRectWithSize:CGSizeMake(width - 32, CGFLOAT_MAX)
                     options:NSStringDrawingUsesLineFragmentOrigin
                  attributes:@{NSFontAttributeName: AppIconDetailFont()}
                     context:nil];
    return CGSizeMake(width, ceil(CGRectGetHeight(textRect)) + 36);
}

#pragma mark - Flow layout sizing

- (CGSize)collectionView:(UICollectionView*)cv
                    layout:(UICollectionViewLayout*)layout
    sizeForItemAtIndexPath:(NSIndexPath*)indexPath {
    UICollectionViewFlowLayout* flow = (UICollectionViewFlowLayout*)layout;
    CGFloat available = CGRectGetWidth(cv.bounds) - flow.sectionInset.left -
                        flow.sectionInset.right -
                        flow.minimumInteritemSpacing * 2;
    CGFloat scale = UIScreen.mainScreen.scale ?: 1;
    CGFloat width = MIN(floor(available / 3.0 * scale) / scale, 96.0);
    return CGSizeMake(width, width + 38.0);
}

@end
