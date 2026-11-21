#import "../HookHelpers.h"

#define LOCATION_NOTE         @"AccountLocationUpdated"
#define MAX_SOURCE_CACHE_SIZE 200
#define MAX_FETCH_RETRIES     3

static NSMutableDictionary* accountLocations = nil;
static NSMutableDictionary* locationPending = nil;
static NSMutableDictionary* locationRetries = nil;
static NSString* const kAboutAccountQueryID = @"XRqGa7EeokUU5kppkh13EA";

static char kFooterComposedKey;
static char kFooterTweetIDKey;    // the tweet ID a footer text view is currently showing
static char kFooterScreenNameKey; // the author handle a footer text view is currently showing
static char kFooterObservingKey;  // whether a footer text view registered for update notifications

NSString* encodedQueryParameter(id object);
NSDictionary* dictionaryValue(id container, NSString* key);
NSMutableURLRequest* webGraphQLRequest(NSURL* url);
NSDictionary* jsonFromResponse(NSData* data, NSURLResponse* response, NSError* error);
void pruneCache(NSMutableDictionary* cache, NSString* unavailable,
                NSMutableDictionary* pending, NSMutableDictionary* retries);
NSString* displayableValue(NSString* cached, NSString* unavailable);
NSString* screenNameFromStatus(id status);
