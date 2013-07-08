/* -*- Mode: C++; tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
/*
 *     Copyright 2010 NorthScale, Inc.
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */

#ifndef MEMORY_TRACKER_H
#define MEMORY_TRACKER_H

#include "config.h"
#include "common.hh"
#include "atomic.hh"

#include <map>

/**
 * This class is used by ep-engine to hook into memcached's memory tracking
 * capabilities.
 */
class MemoryTracker {
public:
    ~MemoryTracker();

    static MemoryTracker *getInstance();

    void getAllocatorStats(std::map<std::string, size_t> &alloc_stats);

    static bool trackingMemoryAllocations();

    void updateStats();

    void getDetailedStats(char* buffer, int size);

    size_t getFragmentation();

    size_t getTotalBytesAllocated();

    size_t getTotalHeapBytes();

private:
    MemoryTracker();

    // Wheter or not we have the ability to accurately track memory allocations
    static bool tracking;
    // Singleton memory tracker
    static MemoryTracker *instance;
    pthread_t statsThreadId;
    allocator_stats stats;
};

#endif /* MEMORY_TRACKER_H */
