//
//  AuthViewController.m
//  NeoFreeBird
//
//  Created by BandarHelal on 25/09/2021.
//

#import "AuthViewController.h"
#import "Core/BHTBundle.h"
#import <LocalAuthentication/LocalAuthentication.h>

@interface AuthViewController ()

@property (nonatomic, strong) LAContext* authenticationContext;
@property (nonatomic, strong) UIButton* unlockButton;
@property (nonatomic) NSUInteger authenticationGeneration;
@property (nonatomic) BOOL needsForegroundRetry;
@property (nonatomic) BOOL pendingSuccess;

@end

@implementation AuthViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UIImageView* icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.labelColor;

    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"PADLOCK_LOCKED_LABEL"];
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;

    self.unlockButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.unlockButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.unlockButton setTitle:@"Unlock" forState:UIControlStateNormal];
    self.unlockButton.titleLabel.font =
        [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [self.unlockButton addTarget:self
                          action:@selector(retryAuthentication)
                forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:icon];
    [self.view addSubview:label];
    [self.view addSubview:self.unlockButton];
    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor
                                          constant:-40],
        [label.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:12],
        [self.unlockButton.centerXAnchor
            constraintEqualToAnchor:self.view.centerXAnchor],
        [self.unlockButton.topAnchor constraintEqualToAnchor:label.bottomAnchor
                                                   constant:24]
    ]];
}

- (void)retryAuthentication {
    if (!self.isViewLoaded || !self.view.window || self.authenticationContext ||
        UIApplication.sharedApplication.applicationState !=
            UIApplicationStateActive)
        return;

    LAContext* context = [[LAContext alloc] init];
    NSError* error = nil;
    LAPolicy policy = LAPolicyDeviceOwnerAuthenticationWithBiometrics;
    if (![self canEvaluateBiometrics] ||
        ![context canEvaluatePolicy:policy error:&error]) {
        policy = LAPolicyDeviceOwnerAuthentication;
        if (![context canEvaluatePolicy:policy error:&error]) {
            self.unlockButton.enabled = YES;
            return;
        }
    }

    self.authenticationContext = context;
    self.needsForegroundRetry = NO;
    self.pendingSuccess = NO;
    NSUInteger generation = ++self.authenticationGeneration;
    self.unlockButton.enabled = NO;
    NSString* reason = policy == LAPolicyDeviceOwnerAuthenticationWithBiometrics
                           ? @"Touch ID or Face ID is required to use Twitter"
                           : @"Passcode is required to use Twitter";
    [context evaluatePolicy:policy
            localizedReason:reason
                      reply:^(BOOL success, NSError* _Nullable error) {
                          dispatch_async(dispatch_get_main_queue(), ^{
                              if (self.authenticationContext != context)
                                  return;
                              self.authenticationContext = nil;
                              self.unlockButton.enabled = YES;
                              if (UIApplication.sharedApplication.applicationState ==
                                  UIApplicationStateBackground)
                                  return;
                              if (success &&
                                  UIApplication.sharedApplication.applicationState ==
                                      UIApplicationStateInactive) {
                                  self.pendingSuccess = YES;
                                  self.unlockButton.enabled = NO;
                                  return;
                              }
                              [self finishWithResult:success
                                               error:error
                                          generation:generation];
                          });
                      }];
}

- (void)pauseAuthentication {
    self.needsForegroundRetry = YES;
    self.pendingSuccess = NO;
    ++self.authenticationGeneration;
    LAContext* context = self.authenticationContext;
    self.authenticationContext = nil;
    [context invalidate];
    self.unlockButton.enabled = YES;
}

- (void)resumeAuthenticationIfNeeded {
    if (self.pendingSuccess) {
        self.pendingSuccess = NO;
        if (self.completion)
            self.completion(YES);
    } else if (self.needsForegroundRetry) {
        [self retryAuthentication];
    }
}

- (void)finishWithResult:(BOOL)success
                  error:(NSError*)error
             generation:(NSUInteger)generation {
    if (error) {
        NSLog(@"%@", error);
    }

    if (success && generation == self.authenticationGeneration && self.completion)
        self.completion(YES);
}

// Biometric prompts require NSFaceIDUsageDescription in the host app's Info.plist.
- (BOOL)canEvaluateBiometrics {
    return [[NSBundle mainBundle] infoDictionary][@"NSFaceIDUsageDescription"] != nil;
}

@end
