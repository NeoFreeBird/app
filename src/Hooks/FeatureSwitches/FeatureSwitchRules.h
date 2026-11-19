#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, BHTFeatureSwitchPolicy) {
    BHTFeatureSwitchPolicySetting,
    BHTFeatureSwitchPolicyTabGate,
    BHTFeatureSwitchPolicyBranding,
    BHTFeatureSwitchPolicyPremium,
};

@interface BHTFeatureSwitchRule : NSObject
@property (nonatomic, copy, readonly) NSSet<NSString*>* keys;
@property (nonatomic, copy, readonly) NSString* prefix;
@property (nonatomic, copy, readonly) NSString* suffix;
@property (nonatomic, copy, readonly) NSString* setting;
@property (nonatomic, strong, readonly) NSNumber* enabledValue;
@property (nonatomic, strong, readonly) NSNumber* disabledValue;
@property (nonatomic, readonly) BHTFeatureSwitchPolicy policy;
@end

NSArray<BHTFeatureSwitchRule*>* BHTFeatureSwitchRules(void);
BHTFeatureSwitchRule* BHTFixedSwitches(NSArray<NSString*>* keys, NSNumber* value);
BHTFeatureSwitchRule* BHTSettingSwitches(NSArray<NSString*>* keys, NSString* setting,
                                         NSNumber* enabledValue, NSNumber* disabledValue);
BHTFeatureSwitchRule* BHTPatternSwitches(NSString* prefix, NSString* suffix, NSString* setting,
                                         NSNumber* enabledValue, NSNumber* disabledValue);
BHTFeatureSwitchRule* BHTTabGateSwitches(NSArray<NSString*>* keys);
BHTFeatureSwitchRule* BHTBrandedSwitches(NSArray<NSString*>* keys, NSNumber* twitterValue,
                                         NSNumber* otherValue);
BHTFeatureSwitchRule* BHTPremiumSwitches(NSArray<NSString*>* keys);
