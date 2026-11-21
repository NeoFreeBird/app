#import "Tenor.h"

@implementation BHTTenorURLProtocol {
    NSURLSessionDataTask* _task;
}

+ (BOOL)canInitWithRequest:(NSURLRequest*)request {
    if (![BHTSettings boolForKey:@"use_tenor_gifs"]) {
        return NO;
    }
    if ([NSURLProtocol propertyForKey:TenorPassThroughKey inRequest:request]) {
        return NO;
    }
    return operationForRequest(request) != BHTGifOperationNone;
}

+ (NSURLRequest*)canonicalRequestForRequest:(NSURLRequest*)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest*)a toRequest:(NSURLRequest*)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}

// A private session so our Tenor and pass-through traffic never re-enters the
// protocol stack we're installed into.
+ (NSURLSession*)fetchSession {
    static NSURLSession* session = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSURLSessionConfiguration* configuration =
            [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.protocolClasses = @[];
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

- (void)startLoading {
    NSDictionary* variables = variablesFromRequest(self.request);
    BHTGifOperation operation = operationForRequest(self.request);
    NSURL* url = tenorURLForOperation(operation, variables);
    if (!url) {
        [self loadOriginalRequest];
        return;
    }

    NSString* format = stringValue(variables[@"image_format"]) ?: @"Gif";

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = TenorRequestTimeout;

    __weak __typeof__(self) weakSelf = self;
    _task = [[BHTTenorURLProtocol fetchSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
              __strong __typeof__(weakSelf) self = weakSelf;
              if (!self) {
                  return;
              }

              NSHTTPURLResponse* http = [response isKindOfClass:[NSHTTPURLResponse class]]
                                            ? (NSHTTPURLResponse*)response
                                            : nil;
              NSData* payload = (error || http.statusCode != 200)
                                    ? nil
                                    : payloadForOperation(operation, data, format);

              // Tenor unreachable, rate-limited or empty: X's own results beat none.
              if (!payload) {
                  [self loadOriginalRequest];
                  return;
              }
              [self finishWithPayload:payload];
          }];
    [_task resume];
}

- (void)stopLoading {
    [_task cancel];
    _task = nil;
}

- (void)finishWithPayload:(NSData*)payload {
    NSHTTPURLResponse* response =
        [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:@{
                                      @"Content-Type": @"application/json; charset=utf-8",
                                      @"Content-Length": [@(payload.length) stringValue],
                                  }];

    [self.client URLProtocol:self
          didReceiveResponse:response
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:payload];
    [self.client URLProtocolDidFinishLoading:self];
}

// Replay the untouched X request and hand its response back verbatim.
- (void)loadOriginalRequest {
    NSMutableURLRequest* passthrough = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:TenorPassThroughKey inRequest:passthrough];

    __weak __typeof__(self) weakSelf = self;
    _task = [[BHTTenorURLProtocol fetchSession]
        dataTaskWithRequest:passthrough
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
              __strong __typeof__(weakSelf) self = weakSelf;
              if (!self) {
                  return;
              }

              if (error || !response) {
                  [self.client URLProtocol:self
                          didFailWithError:error ?: [NSError errorWithDomain:NSURLErrorDomain
                                                                        code:NSURLErrorUnknown
                                                                    userInfo:nil]];
                  return;
              }

              [self.client URLProtocol:self
                    didReceiveResponse:response
                    cacheStoragePolicy:NSURLCacheStorageNotAllowed];
              if (data.length) {
                  [self.client URLProtocol:self didLoadData:data];
              }
              [self.client URLProtocolDidFinishLoading:self];
          }];
    [_task resume];
}

@end

// MARK: - Installation

%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration*)defaultSessionConfiguration {
    NSURLSessionConfiguration* configuration = %orig;
    installTenorProtocol(configuration);
    return configuration;
}

+ (NSURLSessionConfiguration*)ephemeralSessionConfiguration {
    NSURLSessionConfiguration* configuration = %orig;
    installTenorProtocol(configuration);
    return configuration;
}

%end

%hook NSURLSession

+ (NSURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration*)configuration {
    installTenorProtocol(configuration);
    return %orig;
}

+ (NSURLSession*)sessionWithConfiguration:(NSURLSessionConfiguration*)configuration
                                 delegate:(id)delegate
                            delegateQueue:(NSOperationQueue*)queue {
    installTenorProtocol(configuration);
    return %orig;
}

%end

%ctor {
    [NSURLProtocol registerClass:[BHTTenorURLProtocol class]];

    %init;
}
