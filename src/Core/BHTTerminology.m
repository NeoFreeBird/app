#import "BHTTerminology.h"

NSDictionary<NSString*, NSString*>* BHTLoadTerminologyTable(NSString* path) {
    NSData* data = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data.length) return @{};
    id table = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:NULL];
    if (![table isKindOfClass:[NSDictionary class]]) return @{};
    for (id key in table) {
        if (![key isKindOfClass:[NSString class]] ||
            ![table[key] isKindOfClass:[NSString class]]) return @{};
    }
    return table;
}

@interface BHTTerminology ()
@property (nonatomic, copy) NSDictionary* replacements;
@property (nonatomic, copy) NSDictionary* phrases;
@property (nonatomic, strong) NSRegularExpression* regex;
@end

@implementation BHTTerminology
- (instancetype)initWithWords:(NSDictionary<NSString*, NSString*>*)words
                      phrases:(NSDictionary<NSString*, NSString*>*)phrases
                       locale:(NSLocale*)locale {
    if ((self = [super init])) {
        self.phrases = phrases;
        NSMutableDictionary* replacements = [NSMutableDictionary dictionary];
        for (NSString* word in words) {
            NSString* replacement = words[word];
            if (!word.length || !replacement.length) continue;
            // Explicit locale-aware variants avoid ICU's locale-independent
            // case folding (notably Turkish i / İ and ı / I).
            if ([word isEqualToString:[word lowercaseStringWithLocale:locale]]) {
                replacements[[word uppercaseStringWithLocale:locale]] =
                    [replacement uppercaseStringWithLocale:locale];
                NSRange first = [word rangeOfComposedCharacterSequenceAtIndex:0];
                NSString* capitalized = [word stringByReplacingCharactersInRange:first
                                                                      withString:[[word substringWithRange:first] uppercaseStringWithLocale:locale]];
                NSRange replacementFirst = [replacement rangeOfComposedCharacterSequenceAtIndex:0];
                replacements[capitalized] = [replacement stringByReplacingCharactersInRange:replacementFirst
                                                                                 withString:[[replacement substringWithRange:replacementFirst] uppercaseStringWithLocale:locale]];
            }
        }
        // Explicit spellings take precedence over generated case variants.
        for (NSString* word in words) {
            if (word.length && [words[word] length]) replacements[word] = words[word];
        }
        self.replacements = replacements;
        NSArray* tokens = [[replacements allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString* a, NSString* b) {
            if (a.length != b.length) return a.length > b.length ? NSOrderedAscending : NSOrderedDescending;
            return [a compare:b];
        }];
        NSMutableArray* patterns = [NSMutableArray array];
        NSRegularExpression* cjk = [NSRegularExpression regularExpressionWithPattern:
                                                            @"[\\p{Han}\\p{Hiragana}\\p{Katakana}]"
                                                                             options:0
                                                                               error:nil];
        for (NSString* token in tokens) {
            NSString* escaped = [NSRegularExpression escapedPatternForString:token];
            BOOL startsCJK = [cjk firstMatchInString:token options:0 range:NSMakeRange(0, 1)] != nil;
            BOOL endsCJK = [cjk firstMatchInString:token options:0 range:NSMakeRange(token.length - 1, 1)] != nil;
            // CJK terms adjoin particles/other words without whitespace. Latin
            // terms still need boundaries, but may also adjoin CJK characters.
            NSString* wordCharacter = @"[\\p{L}\\p{M}\\p{N}_&&[^\\p{Han}\\p{Hiragana}\\p{Katakana}]]";
            NSString* left = startsCJK ? @"" : [NSString stringWithFormat:@"(?<!%@)", wordCharacter];
            NSString* right = endsCJK ? @"" : [NSString stringWithFormat:@"(?!%@)", wordCharacter];
            [patterns addObject:[NSString stringWithFormat:@"%@%@%@", left, escaped, right]];
        }
        if (patterns.count) {
            self.regex = [NSRegularExpression regularExpressionWithPattern:
                                                  [patterns componentsJoinedByString:@"|"]
                                                                   options:0
                                                                     error:nil];
        }
    }
    return self;
}

- (NSArray<NSDictionary*>*)editsForString:(NSString*)input {
    if (!input.length) return nil;
    NSString* phrase = self.phrases[input];
    if (phrase) {
        return [phrase isEqualToString:input] ? nil : @[@{
            @"range": [NSValue valueWithRange:NSMakeRange(0, input.length)],
            @"repl": phrase
        }];
    }
    NSMutableArray* edits = [NSMutableArray array];
    for (NSTextCheckingResult* match in [self.regex matchesInString:input options:0 range:NSMakeRange(0, input.length)]) {
        NSString* token = [input substringWithRange:match.range];
        NSString* replacement = self.replacements[token];
        if (replacement && ![token isEqualToString:replacement]) {
            [edits addObject:@{@"range": [NSValue valueWithRange:match.range], @"repl": replacement}];
        }
    }
    return edits.count ? edits : nil;
}
@end
