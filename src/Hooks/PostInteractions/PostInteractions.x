#import "PostInteractions.h"

%hook T1PostInteractionsViewController

- (void)viewWillLayoutSubviews {
    %orig;
    BHTUpdatePostInteractionTitle(self);
}

+ (id)viewControllerWithAccount:(TFNTwitterAccount*)account
                       statusID:(long long)statusID
                   statusUserID:(long long)statusUserID
                     initialTab:(long long)initialTab {
    T1PostInteractionsViewController* controller =
        %orig(account, statusID, statusUserID, initialTab);
    if (controller != nil) {
        objc_setAssociatedObject(controller, &BHTPostInteractionAccountKey, account,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, &BHTPostInteractionStatusIDKey,
                                 @(statusID), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return controller;
}

- (void)viewDidLoad {
    %orig;
    if (![BHTSettings boolForKey:@"show_quote_numbers"]) {
        return;
    }

    TFNTwitterAccount* account = objc_getAssociatedObject(self, &BHTPostInteractionAccountKey);
    NSNumber* statusID = objc_getAssociatedObject(self, &BHTPostInteractionStatusIDKey);
    if (account == nil || statusID == nil || ![account respondsToSelector:@selector(model)]) {
        return;
    }

    TFNTwitterAccountModel* model = account.model;
    if (model == nil || ![model respondsToSelector:@selector(lookUpStatusForID:completionBlock:)]) {
        return;
    }

    __weak T1PostInteractionsViewController* weakSelf = self;
    [model lookUpStatusForID:statusID.longLongValue
             completionBlock:^(TFNTwitterStatus* status) {
                 dispatch_async(dispatch_get_main_queue(), ^{
                     BHTSetPostInteractionCounts(weakSelf, status);
                 });
             }];
}

%end
