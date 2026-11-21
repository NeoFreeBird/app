//
//  CustomTabBarUtility.h
//  NeoFreeBird
//
//  Created by Bandar Alruwaili on 10/12/2023.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CustomTabBarUtility : NSObject

+ (BOOL)usesNativeEditor;
+ (nullable UIViewController*)editorForAccount:(nullable id)account;

@end

NS_ASSUME_NONNULL_END
