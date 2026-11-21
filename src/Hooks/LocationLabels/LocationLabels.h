#import "../HookHelpers.h"

#define LOCATION_NOTE         @"AccountLocationUpdated"
#define MAX_SOURCE_CACHE_SIZE 200
#define MAX_FETCH_RETRIES     3

static char kFooterObservingKey;
static char kFooterScreenNameKey;
static char kFooterTweetIDKey;
static char kFooterComposedKey;

static NSString* const kAboutAccountQueryID = @"XRqGa7EeokUU5kppkh13EA";
static NSMutableDictionary* locationRetries = nil;
static NSMutableDictionary* locationPending = nil;
static NSMutableDictionary* accountLocations = nil;

NSString* encodedQueryParameter(id object);
NSDictionary* dictionaryValue(id container, NSString* key);
NSMutableURLRequest* webGraphQLRequest(NSURL* url);
NSDictionary* jsonFromResponse(NSData* data, NSURLResponse* response, NSError* error);
void pruneCache(NSMutableDictionary* cache, NSString* unavailable,
                NSMutableDictionary* pending, NSMutableDictionary* retries);
NSString* displayableValue(NSString* cached, NSString* unavailable);
NSString* screenNameFromStatus(id status);
