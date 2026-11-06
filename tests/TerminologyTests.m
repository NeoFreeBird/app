#import <Foundation/Foundation.h>
#import "Core/BHTTerminology.h"

static NSDictionary* Table(NSString* language, NSString* name) {
    NSString* path = [NSString stringWithFormat:@"layout/Library/Application Support/BHT/BHTwitter.bundle/%@.lproj/%@.strings", language, name];
    return BHTLoadTerminologyTable(path);
}

static void Check(NSString* language, NSString* input, NSString* expected) {
    BHTTerminology* matcher = [[BHTTerminology alloc] initWithWords:Table(language, @"RenameWords")
                                                            phrases:Table(language, @"RenamePhrases")
                                                             locale:[NSLocale localeWithLocaleIdentifier:language]];
    NSMutableString* result = [input mutableCopy];
    for (NSDictionary* edit in [[matcher editsForString:input] reverseObjectEnumerator]) {
        [result replaceCharactersInRange:[edit[@"range"] rangeValue] withString:edit[@"repl"]];
    }
    if (![result isEqualToString:expected]) {
        NSLog(@"FAIL %@: %@ -> %@ (expected %@)", language, input, result, expected);
        exit(1);
    }
    if ([matcher editsForString:result].count) {
        NSLog(@"FAIL repeated renaming: %@", result);
        exit(1);
    }
}

static void CheckTableLoading(void) {
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSArray* invalid = @[@"\"post\" = \"Tweet\"", @"\"post\" = \"unterminated", @"", @"(one, two)"];
    for (NSString* source in invalid) {
        [source writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSCAssert(BHTLoadTerminologyTable(path).count == 0, @"Invalid table must be ignored");
    }
    NSDictionary* expected = @{@"post": @"Tweet"};
    for (NSNumber* format in @[@(NSPropertyListXMLFormat_v1_0), @(NSPropertyListBinaryFormat_v1_0)]) {
        NSData* data = [NSPropertyListSerialization dataWithPropertyList:expected format:format.unsignedIntegerValue options:0 error:nil];
        [data writeToFile:path atomically:YES];
        NSCAssert([BHTLoadTerminologyTable(path) isEqual:expected], @"Packaged tables must load");
    }
    NSData* invalidValues = [NSPropertyListSerialization dataWithPropertyList:@{@"post": @42} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    [invalidValues writeToFile:path atomically:YES];
    NSCAssert(BHTLoadTerminologyTable(path).count == 0, @"Non-string values must be ignored");
    [@"\"post\" = \"Tweet\";" writeToFile:path atomically:YES encoding:NSUTF16StringEncoding error:nil];
    NSCAssert([BHTLoadTerminologyTable(path) isEqual:expected], @"UTF-16 tables must load");
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSCAssert(BHTLoadTerminologyTable(path).count == 0, @"Missing tables must be ignored");
}

int main(void) {
    @autoreleasepool {
        CheckTableLoading();
        Check(@"en", @"Posts and REPOSTS on X", @"Tweets and RETWEETS on Twitter");
        Check(@"en", @"x Xcode compost posting", @"x Xcode compost Tweeting");
        Check(@"en", @"Nothing to see here — yet.", @"This tweet has been deleted.");
        Check(@"tr", @"GÖNDERİLER", @"TWEETLER");
        Check(@"tr", @"YENİDEN GÖNDERİLER", @"RETWEETLER");
        Check(@"tr", @"Alıntı", @"Tweeti Alıntıla");
        Check(@"tr", @"alıntı metni", @"alıntı metni");
        Check(@"pl", @"We wpisie", @"W Tweecie");
        Check(@"pl", @"Podaj dalej wpis", @"Podaj dalej");
        Check(@"pl", @"Opublikuj", @"Tweetnij");
        Check(@"pl", @"opublikuj artykuł", @"opublikuj artykuł");
        Check(@"ja", @"新しいポストを見る", @"新しいツイートを見る");
        Check(@"ja", @"リポストしました", @"リツイートしました");
        Check(@"ja", @"Xでポストする", @"Twitterでツイートする");
        Check(@"zh_CN", @"查看帖子和正在转帖", @"查看推文和正在转推");
        Check(@"zh-Hant", @"查看貼文", @"查看推文");
        Check(@"zh-Hant", @"發佈", @"推文");
        Check(@"zh-Hant", @"發佈影片", @"發佈影片");
        Check(@"fr", @"Republication en cours", @"Retweet en cours");
        Check(@"de", @"Posts on X", @"Posts on X");
        Check(@"en", @"", @"");
        NSLog(@"All terminology regression checks passed");
    }
}
