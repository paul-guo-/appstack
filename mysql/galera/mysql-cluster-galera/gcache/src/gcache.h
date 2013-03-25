/*
 * Copyright (C) 2010 Codership Oy <info@codership.com>
 */
/*!
 * @file C-interface to GCache.
 */

#ifndef _gcache_h_
#define _gcache_h_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#include "gu_config.h"

typedef struct _gcache gcache_t;

gcache_t* gcache_create   (gu_config_t* conf, const char* data_dir);
void      gcache_destroy  (gcache_t* gc);

void* gcache_malloc       (gcache_t* gc, size_t size);
void  gcache_free         (gcache_t* gc, const void* ptr);
void* gcache_realloc      (gcache_t* gc, void* ptr, size_t size);

#if 0 /* REMOVE */
void  gcache_seqno_init   (gcache_t* gc, int64_t seqno);
void  gcache_seqno_assign (gcache_t* gc, const void* ptr, int64_t seqno);
void  gcache_seqno_release(gcache_t* gc);
#endif

#ifdef __cplusplus
}
#endif

#endif /* _gcache_h_ */
