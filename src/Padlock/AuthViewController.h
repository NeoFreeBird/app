//
//  AuthViewController.h
//  NeoFreeBird
//
//  Created by BandarHelal on 25/09/2021.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AuthViewController : UIViewController

// Called on the main queue after successful authentication.
@property (nonatomic, copy, nullable) void (^completion)(BOOL authenticated);

// Starts a fresh authentication attempt when the user taps Unlock.
- (void)retryAuthentication;
- (void)pauseAuthentication;
- (void)resumeAuthenticationIfNeeded;

@end

NS_ASSUME_NONNULL_END
