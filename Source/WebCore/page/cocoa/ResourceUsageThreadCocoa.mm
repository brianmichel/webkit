/*
 * Copyright (C) 2015 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "ResourceUsageThread.h"

#if ENABLE(RESOURCE_USAGE)

#include "MachVMSPI.h"
#include <JavaScriptCore/GCActivityCallback.h>
#include <heap/Heap.h>
#include <mach/mach.h>
#include <mach/vm_statistics.h>
#include <runtime/VM.h>
#include <sys/sysctl.h>

namespace WebCore {

static size_t vmPageSize()
{
    static size_t pageSize;
    static std::once_flag onceFlag;
    std::call_once(onceFlag, [&] {
        size_t outputSize = sizeof(pageSize);
        int status = sysctlbyname("vm.pagesize", &pageSize, &outputSize, nullptr, 0);
        ASSERT_UNUSED(status, status != -1);
        ASSERT(pageSize);
    });
    return pageSize;
}

struct TagInfo {
    TagInfo() { }
    size_t dirty { 0 };
    size_t reclaimable { 0 };
};

static std::array<TagInfo, 256> pagesPerVMTag()
{
    std::array<TagInfo, 256> tags;
    task_t task = mach_task_self();
    mach_vm_size_t size;
    uint32_t depth = 0;
    struct vm_region_submap_info_64 info = { };
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
    for (mach_vm_address_t addr = 0; ; addr += size) {
        int purgeableState;
        if (mach_vm_purgable_control(task, addr, VM_PURGABLE_GET_STATE, &purgeableState) != KERN_SUCCESS)
            purgeableState = VM_PURGABLE_DENY;

        kern_return_t kr = mach_vm_region_recurse(task, &addr, &size, &depth, (vm_region_info_t)&info, &count);
        if (kr != KERN_SUCCESS)
            break;

        if (purgeableState == VM_PURGABLE_VOLATILE) {
            tags[info.user_tag].reclaimable += info.pages_resident;
            continue;
        }

        if (purgeableState == VM_PURGABLE_EMPTY) {
            tags[info.user_tag].reclaimable += size / vmPageSize();
            continue;
        }

        bool anonymous = !info.external_pager;
        if (anonymous) {
            tags[info.user_tag].dirty += info.pages_resident - info.pages_reusable;
            tags[info.user_tag].reclaimable += info.pages_reusable;
        } else
            tags[info.user_tag].dirty += info.pages_dirtied;
    }

    return tags;
}

static float cpuUsage()
{
    thread_array_t threadList;
    mach_msg_type_number_t threadCount;
    kern_return_t kr = task_threads(mach_task_self(), &threadList, &threadCount);
    if (kr != KERN_SUCCESS)
        return -1;

    float usage = 0;

    for (mach_msg_type_number_t i = 0; i < threadCount; ++i) {
        thread_info_data_t threadInfo;
        thread_basic_info_t threadBasicInfo;

        mach_msg_type_number_t threadInfoCount = THREAD_INFO_MAX;
        kr = thread_info(threadList[i], THREAD_BASIC_INFO, static_cast<thread_info_t>(threadInfo), &threadInfoCount);
        if (kr != KERN_SUCCESS)
            return -1;

        threadBasicInfo = reinterpret_cast<thread_basic_info_t>(threadInfo);

        if (!(threadBasicInfo->flags & TH_FLAGS_IDLE))
            usage += threadBasicInfo->cpu_usage / static_cast<float>(TH_USAGE_SCALE) * 100.0;
    }

    kr = vm_deallocate(mach_task_self(), (vm_offset_t)threadList, threadCount * sizeof(thread_t));
    ASSERT(kr == KERN_SUCCESS);

    return usage;
}

static unsigned categoryForVMTag(unsigned tag)
{
    switch (tag) {
    case VM_MEMORY_IOKIT:
    case VM_MEMORY_LAYERKIT:
        return MemoryCategory::Layers;
    case VM_MEMORY_IMAGEIO:
    case VM_MEMORY_CGIMAGE:
        return MemoryCategory::Images;
    case VM_MEMORY_JAVASCRIPT_JIT_EXECUTABLE_ALLOCATOR:
        return MemoryCategory::JSJIT;
    case VM_MEMORY_MALLOC:
    case VM_MEMORY_MALLOC_HUGE:
    case VM_MEMORY_MALLOC_LARGE:
    case VM_MEMORY_MALLOC_SMALL:
    case VM_MEMORY_MALLOC_TINY:
    case VM_MEMORY_MALLOC_NANO:
        return MemoryCategory::LibcMalloc;
    case VM_MEMORY_TCMALLOC:
        return MemoryCategory::bmalloc;
    default:
        return MemoryCategory::Other;
    }
};

void ResourceUsageThread::platformThreadBody(JSC::VM* vm, ResourceUsageData& data)
{
    data.cpu = cpuUsage();

    auto tags = pagesPerVMTag();
    std::array<TagInfo, MemoryCategory::NumberOfCategories> pagesPerCategory;
    size_t totalDirtyPages = 0;
    for (unsigned i = 0; i < 256; ++i) {
        pagesPerCategory[categoryForVMTag(i)].dirty += tags[i].dirty;
        pagesPerCategory[categoryForVMTag(i)].reclaimable += tags[i].reclaimable;
        totalDirtyPages += tags[i].dirty;
    }

    for (auto& category : data.categories) {
        if (category.isSubcategory) // Only do automatic tallying for top-level categories.
            continue;
        category.dirtySize = pagesPerCategory[category.type].dirty * vmPageSize();
        category.reclaimableSize = pagesPerCategory[category.type].reclaimable * vmPageSize();
    }
    data.totalDirtySize = totalDirtyPages * vmPageSize();

    size_t currentGCHeapCapacity = vm->heap.blockBytesAllocated();
    size_t currentGCOwned = vm->heap.extraMemorySize();

    data.categories[MemoryCategory::GCHeap].dirtySize = currentGCHeapCapacity;
    data.categories[MemoryCategory::GCOwned].dirtySize = currentGCOwned;

    // Subtract known subchunks from the bmalloc bucket.
    // FIXME: Handle running with bmalloc disabled.
    data.categories[MemoryCategory::bmalloc].dirtySize -= currentGCHeapCapacity + currentGCOwned;

    data.timeOfNextEdenCollection = vm->heap.edenActivityCallback()->nextFireTime();
    data.timeOfNextFullCollection = vm->heap.fullActivityCallback()->nextFireTime();
}

}

#endif
