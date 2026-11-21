#import "Profile.h"

void PresentCopyProfileInfoSheet(T1ProfileUserViewModel* viewModel) {
    NSMutableArray<TFNActionItem*>* items = [NSMutableArray array];

    void (^addCopyItem)(NSString*, NSString*, NSString*) =
        ^(NSString* titleKey, NSString* iconName, NSString* value) {
            if (!value.length) {
                return;
            }
            TFNActionItem* item = [(Class)objc_getClass("TFNActionItem")
                actionItemWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:titleKey]
                          imageName:iconName
                             action:^{
                                 UIPasteboard.generalPasteboard.string = value;
                             }];
            if (item) {
                [items addObject:item];
            }
        };

    addCopyItem(@"COPY_PROFILE_INFO_MENU_OPTION_3", @"account", viewModel.fullName);
    addCopyItem(@"COPY_PROFILE_INFO_MENU_OPTION_2", @"at", viewModel.username);
    addCopyItem(@"COPY_PROFILE_INFO_MENU_OPTION_1", @"news_stroke", viewModel.bio);
    addCopyItem(@"COPY_PROFILE_INFO_MENU_OPTION_5", @"location_stroke", viewModel.location);
    addCopyItem(@"COPY_PROFILE_INFO_MENU_OPTION_4", @"link", viewModel.url);
    if (viewModel.username.length) {
        addCopyItem(@"COPY_PROFILE_INFO_MENU_OPTION_6", @"link",
                    [NSString stringWithFormat:@"https://x.com/%@", viewModel.username]);
    }
    addCopyItem(@"COPY_PROFILE_INFO_MENU_OPTION_7", @"bar_chart", [NSString stringWithFormat:@"%ld", (long)viewModel.userDataSource.user.userID]);
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateStyle = NSDateFormatterLongStyle;
    addCopyItem(@"COPY_PROFILE_INFO_MENU_OPTION_8", @"calendar",
                [dateFormatter stringFromDate:viewModel.userDataSource.user.createdDate]);

    if (!items.count) {
        return;
    }

    TFNMenuSheetViewController* sheet = [[(Class)objc_getClass("TFNMenuSheetViewController") alloc]
        initWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_TITLE"]
          actionItems:items];
    [sheet tfnPresentedCustomPresentFromViewController:topMostController()
                                              animated:YES
                                            completion:nil];
}
