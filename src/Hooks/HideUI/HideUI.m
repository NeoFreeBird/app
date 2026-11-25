#import "HideUI.h"

typedef struct {
    uintptr_t heapHeader[2];
    NSInteger count;
    uintptr_t capacityAndFlags;
    void* pages[];
} BHTHistoryPageStorage;

void HideActivityHistoryTabs(UIViewController* controller) {
    BOOL hideVideos = [BHTSettings boolForKey:@"hide_video_history"];
    BOOL hideArticles = [BHTSettings boolForKey:@"hide_article_history"];
    if (!hideVideos && !hideArticles) {
        return;
    }

    Ivar pagesIvar = class_getInstanceVariable(controller.class, "pageViewControllers");
    if (!pagesIvar) {
        return;
    }

    Class videosClass = NSClassFromString(@"_TtC16XActivityHistory39ActivityHistoryVideosPageViewController");
    Class historyPageClass = NSClassFromString(@"_TtC16XActivityHistory33ActivityHistoryPageViewController");
    Ivar contentTypeIvar = historyPageClass ? class_getInstanceVariable(historyPageClass, "contentType") : NULL;

    static bool (*isUniquelyReferenced)(const void*);
    static void (*releaseObject)(void*);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        isUniquelyReferenced = dlsym(RTLD_DEFAULT, "swift_isUniquelyReferenced_nonNull_native");
        releaseObject = dlsym(RTLD_DEFAULT, "swift_unknownObjectRelease");
    });

    const uint8_t* bytes = (__bridge const void*)controller;
    uintptr_t array = *(const uintptr_t*)(bytes + ivar_getOffset(pagesIvar));
    // Swift's class-element array uses the top two bits and low bit for
    // non-native representations. Only mutate an exclusively owned buffer.
    const uintptr_t nonNativeBits = UINT64_C(0xc000000000000001);
    BHTHistoryPageStorage* storage = (void*)array;
    if (!array || (array & nonNativeBits) || !isUniquelyReferenced || !releaseObject ||
        !isUniquelyReferenced(storage)) {
        return;
    }

    // In XActivityHistory, the generic page uses content type 1 for Articles.
    const uint8_t articlesContentType = 1;
    for (NSInteger index = storage->count - 1; index >= 0 && storage->count > 1; index--) {
        void* page = storage->pages[index];
        __unsafe_unretained UIViewController* viewController = (__bridge UIViewController*)page;
        BOOL remove = hideVideos && videosClass && [viewController isKindOfClass:videosClass];
        if (hideArticles && contentTypeIvar && [viewController isKindOfClass:historyPageClass]) {
            const uint8_t* pageBytes = page;
            remove = pageBytes[ivar_getOffset(contentTypeIvar)] == articlesContentType;
        }
        if (!remove) {
            continue;
        }

        storage->count--;
        memmove(&storage->pages[index], &storage->pages[index + 1],
                (storage->count - index) * sizeof(page));
        storage->pages[storage->count] = NULL;
        releaseObject(page);
    }
}
