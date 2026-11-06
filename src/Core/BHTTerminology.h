#import <Foundation/Foundation.h>

// Missing, malformed, or non-string tables are ignored. Supports packaged plists
// as well as source .strings files, without the throwing NSString parser.
FOUNDATION_EXPORT NSDictionary<NSString*, NSString*>* BHTLoadTerminologyTable(NSString* path);

// Immutable, locale-specific matcher shared by plain and attributed UI text.
@interface BHTTerminology : NSObject
- (instancetype)initWithWords:(NSDictionary<NSString*, NSString*>*)words
                      phrases:(NSDictionary<NSString*, NSString*>*)phrases
                       locale:(NSLocale*)locale;
- (NSArray<NSDictionary*>*)editsForString:(NSString*)input;
@end
