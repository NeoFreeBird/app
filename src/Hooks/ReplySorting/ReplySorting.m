#import "ReplySorting.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <string.h>

// Preserve Swift's calling convention and context register when forwarding.
typedef void* (*ReplySortingStateInitFn)(
    uint8_t mode, void* __attribute__((swift_context)) context) __attribute__((swiftcall));

static ReplySortingStateInitFn originalReplySortingStateInit;
static NSInteger userActionDepth;

#pragma mark - Ranking preferences

// default_reply_sort: 0 unchanged, 1 relevance, 2 recency, 3 likes.
BOOL PreferredReplyRankingMode(uint8_t* mode) {
    switch ([BHTSettings integerForKey:@"default_reply_sort"]) {
        case 1:
            *mode = BHTReplyRankingModeRelevance;
            return YES;
        case 2:
            *mode = BHTReplyRankingModeRecency;
            return YES;
        case 3:
            *mode = BHTReplyRankingModeLikes;
            return YES;
        default:
            return NO;
    }
}

void PerformReplySortingUserAction(void (^action)(void)) {
    userActionDepth++;
    @try {
        action();
    } @finally {
        userActionDepth--;
    }
}

static void* __attribute__((swiftcall)) ReplySortingStateInit(
    uint8_t mode, void* __attribute__((swift_context)) context) {
    uint8_t preferred;
    if (userActionDepth == 0 && PreferredReplyRankingMode(&preferred)) {
        mode = preferred;
    }
    return originalReplySortingStateInit(mode, context);
}

#pragma mark - Bound pointer rebinding

static void ReplaceBoundPointer(void** slot, void* replacement) {
    // __DATA_CONST is read-only after binding. Make only the containing data
    // page writable; the replacement does not modify executable code.
    vm_address_t page = (vm_address_t)slot & ~(vm_address_t)vm_page_mask;
    kern_return_t result = vm_protect(mach_task_self(), page, vm_page_size, false,
                                      VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (result != KERN_SUCCESS) {
        return;
    }

    *slot = replacement;
    vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ);
}

static void RebindSectionPointers(const struct section_64* section, intptr_t slide,
                                  void* target, void* replacement) {
    uint32_t type = section->flags & SECTION_TYPE;
    if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) {
        return;
    }

    void** slots = (void**)((uintptr_t)slide + section->addr);
    uint64_t count = section->size / sizeof(*slots);
    for (uint64_t index = 0; index < count; index++) {
        if (slots[index] == target) {
            ReplaceBoundPointer(&slots[index], replacement);
        }
    }
}

// Match bound addresses: chained fixups can mark the indirect symbol-table
// entries LOCAL ABSOLUTE, so symbol names cannot identify these slots reliably.
static void RebindImagePointers(const struct mach_header_64* header, intptr_t slide,
                                void* target, void* replacement) {
    const struct load_command* command = (const struct load_command*)(header + 1);
    for (uint32_t index = 0; index < header->ncmds; index++) {
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64* segment = (const struct segment_command_64*)command;
            const struct section_64* sections = (const struct section_64*)(segment + 1);
            for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++) {
                RebindSectionPointers(&sections[sectionIndex], slide, target, replacement);
            }
        }
        command = (const struct load_command*)((const uint8_t*)command + command->cmdsize);
    }
}

#pragma mark - Hook installation

static void RebindReplySortingImage(const struct mach_header* header, intptr_t slide) {
    Dl_info info;
    if (!originalReplySortingStateInit || header->magic != MH_MAGIC_64 ||
        !dladdr(header, &info) || !info.dli_fname ||
        !strstr(info.dli_fname, "/T1Twitter.framework/T1Twitter")) {
        return;
    }

    RebindImagePointers((const struct mach_header_64*)header, slide,
                        (void*)originalReplySortingStateInit, (void*)ReplySortingStateInit);
}

void InstallReplySortingStateHook(void) {
    // TFSTwitterCore.ReplySortingState.init(rankingMode:)
    originalReplySortingStateInit = (ReplySortingStateInitFn)dlsym(
        RTLD_DEFAULT,
        "$s14TFSTwitterCore17ReplySortingStateC11rankingModeAC"
        "14GraphQLScalars015TimelineRankingG5InputO_tcfc");

    _dyld_register_func_for_add_image(RebindReplySortingImage);
}
