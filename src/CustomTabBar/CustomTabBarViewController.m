//  CustomTabBarViewController.m
//  NeoFreeBird
//
//  Created by Bandar Alruwaili on 11/12/2023.
//  Modified by actuallyaridan on 31/05/2025.
//
//  Clones the app's native tab-customization screen: a grid of every available
//  tab (tap to add/remove) above a drag-reorderable tab-bar preview row.
//

#import "CustomTabBarViewController.h"
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import "CustomTabBarCell.h"
#import "CustomTabBarNativeColors.h"
#import "CustomTabBarPreviewCell.h"
#import "CustomTabBarUtility.h"

extern UIColor* CurrentAccentColor(void);

// Whether the account genuinely has a panel's tab, ignoring the forced tab
// gates
extern BOOL panelIsGenuinelyAvailable(long long panelID);

// The floating compose button, hidden while the editor is on screen.
@interface TFNFloatingActionButton : UIView
- (void)hideAnimated:(_Bool)animated completion:(id)completion;
@end

// The app's standard button, used for the restore control.
@interface TFNButton : UIButton
+ (id)buttonWithTitle:(id)arg1
           imageNamed:(id)arg2
                style:(long long)arg3
            sizeClass:(long long)arg4;
@end

// The app's tab navigation, asked to recompute its tabs so changes apply live.
@interface T1TabbedAppNavigationViewController : UIViewController
- (void)recalculateVisiblePanels;
@end

static NSString* const kGridHeaderID = @"gridHeader";
static NSString* const kGridFooterID = @"gridFooter";

@interface CustomTabBarViewController () <UICollectionViewDataSource,
                                          UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView* gridView;
@property (nonatomic, strong) UICollectionView* previewView;
@property (nonatomic, strong) UIView* separator;

// All available tab pageIDs; and the selected ones in tab-bar order (Home
// first).
@property (nonatomic, strong) NSMutableArray<NSString*>* allPages;
@property (nonatomic, strong) NSMutableArray<NSString*>* selectedPages;
@property (nonatomic, strong) NSArray<NSString*>* originalSelection;
@property (nonatomic, assign) BOOL hasChanges;
@end

@implementation CustomTabBarViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = CustomTabBarScreenBackgroundColor();
    self.hasChanges = NO;

    [self setupGridView];
    [self setupPreviewRow];
    [self setupSaveButton];
    [self loadData];
    [self updateSaveButtonState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Hide the floating compose button so it doesn't overlap the editor.
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        [self findAndHideFloatingActionButtonInView:window];
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self.gridView.collectionViewLayout invalidateLayout];
    [self.previewView.collectionViewLayout invalidateLayout];
}

- (void)findAndHideFloatingActionButtonInView:(UIView*)view {
    if ([view isKindOfClass:NSClassFromString(@"TFNFloatingActionButton")]) {
        [(TFNFloatingActionButton*)view hideAnimated:YES completion:nil];
        return;
    }
    for (UIView* subview in view.subviews) {
        [self findAndHideFloatingActionButtonInView:subview];
    }
}

#pragma mark - UI Setup

- (void)setupSaveButton {
    UIBarButtonItem* saveButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                             target:self
                             action:@selector(saveButtonTapped)];
    self.navigationItem.rightBarButtonItem = saveButton;
    saveButton.enabled = NO;
}

- (void)setupGridView {
    // Grid metrics mirror the native TabCustomizationGridViewController.
    UICollectionViewFlowLayout* layout =
        [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 20;
    layout.minimumLineSpacing = 24;
    layout.sectionInset = UIEdgeInsetsMake(8, 20, 24, 20);

    self.gridView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                       collectionViewLayout:layout];
    self.gridView.translatesAutoresizingMaskIntoConstraints = NO;
    self.gridView.backgroundColor = [UIColor clearColor];
    self.gridView.alwaysBounceVertical = YES;
    self.gridView.delegate = self;
    self.gridView.dataSource = self;
    [self.gridView registerClass:[CustomTabBarCell class]
        forCellWithReuseIdentifier:[CustomTabBarCell reuseIdentifier]];
    [self.gridView registerClass:[UICollectionReusableView class]
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:kGridHeaderID];
    [self.gridView registerClass:[UICollectionReusableView class]
        forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
               withReuseIdentifier:kGridFooterID];
    [self.view addSubview:self.gridView];
}

- (void)setupPreviewRow {
    UICollectionViewFlowLayout* layout =
        [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 0;
    layout.minimumInteritemSpacing = 0;

    self.previewView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                          collectionViewLayout:layout];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewView.backgroundColor = [UIColor clearColor];
    self.previewView.showsHorizontalScrollIndicator = NO;
    self.previewView.delegate = self;
    self.previewView.dataSource = self;
    [self.previewView registerClass:[CustomTabBarPreviewCell class]
         forCellWithReuseIdentifier:[CustomTabBarPreviewCell reuseIdentifier]];
    [self.view addSubview:self.previewView];

    UILongPressGestureRecognizer* longPress =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handleReorderGesture:)];
    [self.previewView addGestureRecognizer:longPress];

    // Hairline separator above the preview row.
    self.separator = [UIView new];
    self.separator.translatesAutoresizingMaskIntoConstraints = NO;
    self.separator.backgroundColor = CustomTabBarSeparatorColor();
    [self.view addSubview:self.separator];

    CGFloat hairline = 1.0 / UIScreen.mainScreen.scale;
    [NSLayoutConstraint activateConstraints:@[
        [self.previewView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.previewView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.previewView.bottomAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.previewView.heightAnchor constraintEqualToConstant:49],

        [self.separator.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.separator.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.separator.bottomAnchor
            constraintEqualToAnchor:self.previewView.topAnchor],
        [self.separator.heightAnchor constraintEqualToConstant:hairline],

        [self.gridView.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.gridView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.gridView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.gridView.bottomAnchor
            constraintEqualToAnchor:self.separator.topAnchor]
    ]];
}

#pragma mark - Data

- (void)loadData {
    // Offer the captured tabs the account genuinely has; panels that only exist
    // because of the tweak's forced gates stay out of the grid.
    self.allPages = [NSMutableArray array];
    for (NSDictionary* entry in [CustomTabBarUtility availableTabs]) {
        NSNumber* panelID = entry[TabPanelIDKey];
        if (panelID && !panelIsGenuinelyAvailable(panelID.longLongValue)) {
            continue;
        }
        [self.allPages addObject:entry[TabPageKey]];
    }

    NSArray<NSString*>* saved = [CustomTabBarUtility visiblePageIDsInOrder];
    NSArray<NSString*>* source =
        saved ?: [CustomTabBarUtility defaultVisiblePageIDs];

    self.selectedPages = [NSMutableArray array];
    for (NSString* page in source) {
        if ([self.allPages containsObject:page] &&
            ![self.selectedPages containsObject:page]) {
            [self.selectedPages addObject:page];
        }
    }
    [self pinHomeFirst];
    [self trimSelectionToCapacity];

    self.originalSelection = [self.selectedPages copy];
    self.hasChanges = NO;

    [self.gridView reloadData];
    [self.previewView reloadData];
}

- (void)pinHomeFirst {
    [self.selectedPages removeObject:CustomTabBarHomePageID];
    if ([CustomTabBarUtility metadataForPage:CustomTabBarHomePageID]) {
        [self.selectedPages insertObject:CustomTabBarHomePageID atIndex:0];
    }
}

#pragma mark - Capacity

// The app shows at most this many tabs and drops the rest, so the editor
// doesn't let the selection grow past it.
- (NSInteger)tabCapacity {
    UITraitCollection* traits = self.view.window.traitCollection;
    if (!traits ||
        traits.horizontalSizeClass == UIUserInterfaceSizeClassUnspecified) {
        traits = UIScreen.mainScreen.traitCollection;
    }
    return [CustomTabBarUtility tabBarCapacityForTraitCollection:traits];
}

// More is re-appended whenever the selection is loaded, so it always takes a
// slot when the app has it.
- (NSInteger)occupiedTabCount {
    NSInteger count = (NSInteger)self.selectedPages.count;
    if ([self.allPages containsObject:CustomTabBarMorePageID] &&
        ![self.selectedPages containsObject:CustomTabBarMorePageID]) {
        count++;
    }
    return count;
}

// Drops the trailing picks of a selection saved before the cap existed, so the
// preview matches what the bar can actually show.
- (void)trimSelectionToCapacity {
    NSInteger capacity = [self tabCapacity];
    while ([self occupiedTabCount] > capacity) {
        NSUInteger index = [self.selectedPages
            indexOfObjectWithOptions:NSEnumerationReverse
                         passingTest:^BOOL(NSString* page, NSUInteger idx, BOOL* stop) {
                             return ![page isEqualToString:CustomTabBarHomePageID] &&
                                    ![page isEqualToString:CustomTabBarMorePageID];
                         }];
        if (index == NSNotFound) {
            break;
        }
        [self.selectedPages removeObjectAtIndex:index];
    }
}

- (void)recomputeChanges {
    self.hasChanges = ![self.selectedPages isEqualToArray:self.originalSelection];
    [self updateSaveButtonState];
}

- (void)updateSaveButtonState {
    self.navigationItem.rightBarButtonItem.enabled = self.hasChanges;
}

#pragma mark - Save / Reset

- (void)saveButtonTapped {
    [self persistChanges];

    // Apply the new layout live by asking the app to recompute its visible tabs;
    // this re-runs the tab-entry hook with the freshly saved order.
    [self applyLiveLayout];
    [self.navigationController popViewControllerAnimated:YES];
}

static UIViewController* findViewControllerOfClass(UIViewController* vc,
                                                   Class cls) {
    if (!vc) {
        return nil;
    }
    if ([vc isKindOfClass:cls]) {
        return vc;
    }
    for (UIViewController* child in vc.childViewControllers) {
        UIViewController* found = findViewControllerOfClass(child, cls);
        if (found) {
            return found;
        }
    }
    return findViewControllerOfClass(vc.presentedViewController, cls);
}

- (BOOL)applyLiveLayout {
    Class navClass = objc_getClass("T1TabbedAppNavigationViewController");
    if (!navClass) {
        return NO;
    }

    UIViewController* tabNav = nil;
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        tabNav = findViewControllerOfClass(window.rootViewController, navClass);
        if (tabNav) {
            break;
        }
    }

    if (![tabNav respondsToSelector:@selector(recalculateVisiblePanels)]) {
        return NO;
    }

    [(T1TabbedAppNavigationViewController*)tabNav recalculateVisiblePanels];
    return YES;
}

- (void)persistChanges {
    [self pinHomeFirst];

    [CustomTabBarUtility setVisiblePageIDs:self.selectedPages];

    self.originalSelection = [self.selectedPages copy];
    self.hasChanges = NO;
    [self updateSaveButtonState];
}

- (void)restoreTapped {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:
            [[BHTBundle sharedBundle]
                localizedStringForKey:
                    @"SUBSCRIPTION_TAB_CUSTOMIZATION_RESTORE_BUTTON_TITLE"]
                         message:[[BHTBundle sharedBundle]
                                     localizedStringForKey:
                                         @"CUSTOM_TAB_BAR_RESET_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedStringForKey:
                                                 @"CONTINUE_ACTION_LABEL"]
                                   style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction* _Nonnull action) {
                                     [CustomTabBarUtility resetSelection];
                                     [self loadData];
                                     [self recomputeChanges];
                                 }]];
    [alert
        addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                     localizedStringForKey:
                                                         @"CANCEL_ACTION_LABEL"]
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Reordering (preview row)

- (void)handleReorderGesture:(UILongPressGestureRecognizer*)gesture {
    CGPoint location = [gesture locationInView:self.previewView];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath* indexPath =
                [self.previewView indexPathForItemAtPoint:location];
            // Home stays pinned first and can't be dragged.
            if (!indexPath || indexPath.item == 0) {
                return;
            }
            [self.previewView beginInteractiveMovementForItemAtIndexPath:indexPath];
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.previewView updateInteractiveMovementTargetPosition:location];
            break;
        case UIGestureRecognizerStateEnded:
            [self.previewView endInteractiveMovement];
            break;
        default:
            [self.previewView cancelInteractiveMovement];
            break;
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView*)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return collectionView == self.gridView ? self.allPages.count
                                           : self.selectedPages.count;
}

- (__kindof UICollectionViewCell*)collectionView:
                                      (UICollectionView*)collectionView
                          cellForItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView == self.previewView) {
        CustomTabBarPreviewCell* cell = [collectionView
            dequeueReusableCellWithReuseIdentifier:[CustomTabBarPreviewCell
                                                       reuseIdentifier]
                                      forIndexPath:indexPath];
        NSDictionary* meta = [CustomTabBarUtility
            metadataForPage:self.selectedPages[indexPath.item]];
        [cell configureWithImageName:meta[TabImageKey]];
        return cell;
    }

    CustomTabBarCell* cell = [collectionView
        dequeueReusableCellWithReuseIdentifier:[CustomTabBarCell reuseIdentifier]
                                  forIndexPath:indexPath];
    NSString* page = self.allPages[indexPath.item];
    NSDictionary* meta = [CustomTabBarUtility metadataForPage:page];
    [cell configureWithTitle:(meta[TabTitleKey] ?: page)
                   imageName:meta[TabImageKey]
                    selected:[self.selectedPages containsObject:page]
                       fixed:[page isEqualToString:CustomTabBarHomePageID]
                 accentColor:CurrentAccentColor()];
    return cell;
}

- (UICollectionReusableView*)collectionView:(UICollectionView*)collectionView
          viewForSupplementaryElementOfKind:(NSString*)kind
                                atIndexPath:(NSIndexPath*)indexPath {
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        UICollectionReusableView* header =
            [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                               withReuseIdentifier:kGridHeaderID
                                                      forIndexPath:indexPath];
        [header.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

        UILabel* label =
            [[UILabel alloc] initWithFrame:CGRectInset(header.bounds, 4, 0)];
        label.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.numberOfLines = 0;
        label.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
        label.textColor = [UIColor secondaryLabelColor];
        label.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"CUSTOM_TAB_BAR_GRID_DETAIL"];
        [header addSubview:label];
        return header;
    }

    UICollectionReusableView* footer =
        [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                           withReuseIdentifier:kGridFooterID
                                                  forIndexPath:indexPath];
    [footer.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSString* title = [[BHTBundle sharedBundle]
        localizedStringForKey:
            @"SUBSCRIPTION_TAB_CUSTOMIZATION_RESTORE_BUTTON_TITLE"];

    UIButton* restore = [objc_getClass("TFNButton") buttonWithTitle:title
                                                         imageNamed:nil
                                                              style:2
                                                          sizeClass:2];
    restore.translatesAutoresizingMaskIntoConstraints = NO;
    [restore addTarget:self
                  action:@selector(restoreTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:restore];
    [NSLayoutConstraint activateConstraints:@[
        [restore.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [restore.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]
    ]];
    return footer;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    // Only the grid toggles selection; the preview row is reorder-only.
    if (collectionView != self.gridView) {
        return;
    }

    NSString* page = self.allPages[indexPath.item];
    if ([page isEqualToString:CustomTabBarHomePageID]) {
        return;
    }

    if ([self.selectedPages containsObject:page]) {
        [self.selectedPages removeObject:page];
    } else {
        BOOL takesNewSlot = ![page isEqualToString:CustomTabBarMorePageID];
        if (takesNewSlot && [self occupiedTabCount] >= [self tabCapacity]) {
            [[UINotificationFeedbackGenerator new]
                notificationOccurred:UINotificationFeedbackTypeWarning];
            return;
        }
        [self.selectedPages addObject:page];
    }

    [self recomputeChanges];
    [self.gridView reloadItemsAtIndexPaths:@[indexPath]];
    [self.previewView reloadData];
}

- (BOOL)collectionView:(UICollectionView*)collectionView
    canMoveItemAtIndexPath:(NSIndexPath*)indexPath {
    return collectionView == self.previewView && indexPath.item != 0;
}

- (NSIndexPath*)collectionView:(UICollectionView*)collectionView
    targetIndexPathForMoveFromItemAtIndexPath:(NSIndexPath*)originalIndexPath
                          toProposedIndexPath:(NSIndexPath*)proposedIndexPath {
    // Keep Home pinned first.
    if (proposedIndexPath.item == 0) {
        return [NSIndexPath indexPathForItem:1 inSection:0];
    }
    return proposedIndexPath;
}

- (void)collectionView:(UICollectionView*)collectionView
    moveItemAtIndexPath:(NSIndexPath*)sourceIndexPath
            toIndexPath:(NSIndexPath*)destinationIndexPath {
    NSString* page = self.selectedPages[sourceIndexPath.item];
    [self.selectedPages removeObjectAtIndex:sourceIndexPath.item];
    [self.selectedPages insertObject:page atIndex:destinationIndexPath.item];
    [self recomputeChanges];
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView*)collectionView
                    layout:(UICollectionViewLayout*)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView == self.previewView) {
        // Native sizes each preview item to 1/6 of the width; full row height.
        CGFloat width = floor(CGRectGetWidth(collectionView.bounds) / 6.0);
        return CGSizeMake(width, CGRectGetHeight(collectionView.bounds));
    }

    UICollectionViewFlowLayout* flow =
        (UICollectionViewFlowLayout*)collectionViewLayout;
    UIEdgeInsets insets = flow.sectionInset;
    CGFloat spacing = flow.minimumInteritemSpacing;

    // Native grid: 3 columns, tile width capped at 98pt, height = width + 27.
    CGFloat available =
        CGRectGetWidth(collectionView.bounds) - insets.left - insets.right;
    CGFloat itemWidth = floor((available - spacing * 2) / 3.0);
    itemWidth = MIN(itemWidth, 98.0);
    return CGSizeMake(itemWidth, itemWidth + 27.0);
}

- (CGSize)collectionView:(UICollectionView*)collectionView
                             layout:
                                 (UICollectionViewLayout*)collectionViewLayout
    referenceSizeForHeaderInSection:(NSInteger)section {
    if (collectionView != self.gridView) {
        return CGSizeZero;
    }
    return CGSizeMake(CGRectGetWidth(collectionView.bounds), 60);
}

- (CGSize)collectionView:(UICollectionView*)collectionView
                             layout:
                                 (UICollectionViewLayout*)collectionViewLayout
    referenceSizeForFooterInSection:(NSInteger)section {
    if (collectionView != self.gridView) {
        return CGSizeZero;
    }
    return CGSizeMake(CGRectGetWidth(collectionView.bounds), 72);
}

@end
