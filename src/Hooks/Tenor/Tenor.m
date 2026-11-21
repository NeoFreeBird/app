#import "Tenor.h"

static NSArray<NSString*>* fullImageKeys(void) {
    return @[@"gif", @"mediumgif", @"tinygif", @"nanogif"];
}

static NSArray<NSString*>* thumbnailKeysForFormat(NSString* format) {
    if ([format isEqualToString:@"Mp4"]) {
        return @[@"tinymp4", @"nanomp4", @"mp4", @"tinygif"];
    }
    return @[@"tinygif", @"nanogif", @"gif"];
}

static NSDictionary* imageNode(NSDictionary* media, NSArray<NSString*>* keys,
                               NSUInteger maxBytes) {
    for (NSString* key in keys) {
        NSDictionary* rendition = media[key];
        if (![rendition isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSString* url = stringValue(rendition[@"url"]);
        if (!url) {
            continue;
        }

        if (maxBytes > 0) {
            NSNumber* size = rendition[@"size"];
            if (![size isKindOfClass:[NSNumber class]] || size.unsignedIntegerValue == 0 ||
                size.unsignedIntegerValue > maxBytes) {
                continue;
            }
        }

        NSArray* dims = rendition[@"dims"];
        if (![dims isKindOfClass:[NSArray class]] || dims.count < 2) {
            continue;
        }

        NSInteger width = [dims[0] integerValue];
        NSInteger height = [dims[1] integerValue];
        if (width <= 0 || height <= 0) {
            continue;
        }

        return @{
            @"__typename": GifImageTypename,
            @"url": url,
            @"width": @(width),
            @"height": @(height),
        };
    }
    return nil;
}

static NSDictionary* gifItemFromResult(NSDictionary* result, NSString* format) {
    if (![result isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString* identifier = stringValue(result[@"id"]);
    if (!identifier) {
        return nil;
    }

    NSArray* mediaList = result[@"media"];
    if (![mediaList isKindOfClass:[NSArray class]] || mediaList.count == 0) {
        return nil;
    }

    NSDictionary* media = mediaList.firstObject;
    if (![media isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary* fullImage = imageNode(media, fullImageKeys(), TenorMaxUploadBytes);
    if (!fullImage) {
        return nil;
    }

    // The id is provider-scoped, not opaque: X's own items come back as
    // `giphy_<providerId>`, so the provider the uploader resolves against is read
    // off the id itself. The web client's Tenor swap relies on the same prefix.
    NSDictionary* thumbnail = imageNode(media, thumbnailKeysForFormat(format), 0) ?: fullImage;
    return @{
        @"__typename": GifItemTypename,
        @"id": [@"tenor_" stringByAppendingString:identifier],
        @"full_image": fullImage,
        @"thumbnail_images": @[thumbnail],
    };
}

static NSData* payloadFromRoot(NSDictionary* root) {
    return [NSJSONSerialization dataWithJSONObject:@{@"data": root} options:0 error:nil];
}

// { data: { <sliceKey>: { __typename, items: [...] } } }
static NSData* gifSlicePayload(NSString* sliceKey, NSDictionary* tenorJSON,
                               NSString* format) {
    NSArray* results = tenorJSON[@"results"];
    if (![results isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSMutableArray<NSDictionary*>* items = [NSMutableArray arrayWithCapacity:results.count];
    for (NSDictionary* result in results) {
        NSDictionary* item = gifItemFromResult(result, format);
        if (item) {
            [items addObject:item];
        }
    }

    // Fallback to GIPHY
    if (items.count == 0) {
        return nil;
    }

    return payloadFromRoot(@{
        sliceKey: @{
            @"__typename": GifSliceTypename,
            @"items": items,
        }
    });
}

static NSData* gifCategoriesPayload(NSDictionary* tenorJSON) {
    NSArray* tags = tenorJSON[@"tags"];
    if (![tags isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSMutableArray<NSDictionary*>* items = [NSMutableArray arrayWithCapacity:tags.count];
    for (NSDictionary* tag in tags) {
        if (![tag isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSString* searchTerm = stringValue(tag[@"searchterm"]);
        NSString* image = stringValue(tag[@"image"]);
        if (!searchTerm || !image) {
            continue;
        }

        // Tenor labels these "#dance"; the picker's chips read better without the hash.
        NSString* displayName = stringValue(tag[@"name"]) ?: searchTerm;
        if ([displayName hasPrefix:@"#"]) {
            displayName = [displayName substringFromIndex:1];
        }

        [items addObject:@{
            @"__typename": GifCategoryTypename,
            @"display_name": displayName.capitalizedString,
            @"name": searchTerm,
            @"thumbnail_images": @[@{@"__typename": GifImageTypename, @"url": image}],
        }];
    }

    if (items.count == 0) {
        return nil;
    }

    return payloadFromRoot(@{
        @"gif_categories_slice": @{
            @"__typename": GifCategorySliceTypename,
            @"items": items,
        }
    });
}

static NSArray<Class>* protocolClassesIncludingTenor(NSArray<Class>* existing) {
    if ([existing containsObject:[BHTTenorURLProtocol class]]) {
        return existing;
    }

    NSMutableArray<Class>* classes = existing ? [existing mutableCopy] : [NSMutableArray array];
    [classes insertObject:[BHTTenorURLProtocol class] atIndex:0];
    return classes;
}

BHTGifOperation operationForRequest(NSURLRequest* request) {
    NSString* path = request.URL.path;
    if (path.length == 0) {
        return BHTGifOperationNone;
    }

    if ([path hasSuffix:@"/GifSearchQuery"]) {
        return BHTGifOperationSearch;
    }
    if ([path hasSuffix:@"/GifEnumerateCategoryQuery"]) {
        return BHTGifOperationCategory;
    }
    if ([path hasSuffix:@"/GifCategoriesQuery"]) {
        return BHTGifOperationCategories;
    }
    return BHTGifOperationNone;
}

NSDictionary* variablesFromRequest(NSURLRequest* request) {
    NSURLComponents* components = [NSURLComponents componentsWithURL:request.URL
                                             resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem* item in components.queryItems) {
        if (![item.name isEqualToString:@"variables"] || item.value.length == 0) {
            continue;
        }

        NSData* data = [item.value dataUsingEncoding:NSUTF8StringEncoding];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            return json;
        }
    }

    NSData* body = request.HTTPBody;
    id json = body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    id variables = json[@"variables"];
    return [variables isKindOfClass:[NSDictionary class]] ? variables : json;
}

NSString* stringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return ((NSString*)value).length ? value : nil;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return ((NSNumber*)value).stringValue;
    }
    return nil;
}

// MARK: - Tenor requests

NSURL* tenorURL(NSString* path, NSDictionary<NSString*, NSString*>* extraParameters) {
    NSURLComponents* components =
        [NSURLComponents componentsWithString:[TenorAPIBase stringByAppendingString:path]];
    if (!components) {
        return nil;
    }

    NSMutableArray<NSURLQueryItem*>* items = [NSMutableArray array];
    [items addObject:[NSURLQueryItem queryItemWithName:@"key" value:TenorAPIKey]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"locale"
                                                 value:[[NSLocale currentLocale] localeIdentifier]]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"contentfilter" value:TenorContentFilter]];

    for (NSString* name in extraParameters) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:extraParameters[name]]];
    }

    components.queryItems = items;
    return components.URL;
}

NSURL* tenorURLForOperation(BHTGifOperation operation, NSDictionary* variables) {
    NSString* limit = [@(TenorResultLimit) stringValue];

    switch (operation) {
        case BHTGifOperationSearch: {
            NSString* query = stringValue(variables[@"query"]);
            if (!query) {
                return nil;
            }
            return tenorURL(@"/search", @{
                @"q": query,
                @"limit": limit,
                @"media_filter": TenorMediaFilter,
            });
        }

        case BHTGifOperationCategory: {
            NSString* category = stringValue(variables[@"category"]);
            if (!category) {
                return nil;
            }
            if ([category caseInsensitiveCompare:@"trending"] == NSOrderedSame) {
                return tenorURL(@"/trending", @{
                    @"limit": limit,
                    @"media_filter": TenorMediaFilter,
                });
            }
            return tenorURL(@"/search", @{
                @"q": category,
                @"limit": limit,
                @"media_filter": TenorMediaFilter,
            });
        }

        case BHTGifOperationCategories:
            return tenorURL(@"/categories", @{@"type": @"featured"});

        case BHTGifOperationNone:
            break;
    }
    return nil;
}

NSData* payloadForOperation(BHTGifOperation operation, NSData* tenorData,
                            NSString* format) {
    id json = tenorData ? [NSJSONSerialization JSONObjectWithData:tenorData options:0 error:nil] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    switch (operation) {
        case BHTGifOperationSearch:
            return gifSlicePayload(@"gif_search_slice", json, format);
        case BHTGifOperationCategory:
            return gifSlicePayload(@"gif_enumerate_category_slice", json, format);
        case BHTGifOperationCategories:
            return gifCategoriesPayload(json);
        case BHTGifOperationNone:
            break;
    }
    return nil;
}

void installTenorProtocol(NSURLSessionConfiguration* configuration) {
    if (configuration) {
        configuration.protocolClasses = protocolClassesIncludingTenor(configuration.protocolClasses);
    }
}
