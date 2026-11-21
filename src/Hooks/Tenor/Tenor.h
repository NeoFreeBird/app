#import "../HookHelpers.h"

static NSString* const TenorAPIBase = @"https://api.tenor.com/v1";
static NSString* const TenorAPIKey = @"3Z0688EVWYKH";
static NSString* const TenorContentFilter = @"medium";
static NSString* const TenorMediaFilter = @"default";
static NSUInteger const TenorResultLimit = 50;
static NSTimeInterval const TenorRequestTimeout = 15.0;
static NSUInteger const TenorMaxUploadBytes = 15 * 1024 * 1024;
static NSString* const GifItemTypename = @"GifItemData";
static NSString* const GifImageTypename = @"GifImage";
static NSString* const GifSliceTypename = @"GifSlice";
static NSString* const GifCategoryTypename = @"GifCategory";
static NSString* const GifCategorySliceTypename = @"GifCategorySlice";
static NSString* const TenorPassThroughKey = @"BHTTenorPassThrough";

// The three operations the GIF picker issues, identified by the trailing path
// component of the persisted-query URL.
typedef NS_ENUM(NSUInteger, BHTGifOperation) {
    BHTGifOperationNone = 0,
    BHTGifOperationSearch,     // GifSearchQuery(query:, image_format:)
    BHTGifOperationCategory,   // GifEnumerateCategoryQuery(category:, image_format:)
    BHTGifOperationCategories, // GifCategoriesQuery(image_format:)
};

BHTGifOperation operationForRequest(NSURLRequest* request);
NSDictionary* variablesFromRequest(NSURLRequest* request);
NSString* stringValue(id value);
NSURL* tenorURL(NSString* path, NSDictionary<NSString*, NSString*>* extraParameters);
NSURL* tenorURLForOperation(BHTGifOperation operation, NSDictionary* variables);
NSData* payloadForOperation(BHTGifOperation operation, NSData* tenorData,
                            NSString* format);
void installTenorProtocol(NSURLSessionConfiguration* configuration);
