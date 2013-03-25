/*
 * Copyright (C) 2008-2010 Codership Oy <info@codership.com>
 *
 * $Id: gcs_backend.c 1865 2010-08-16 21:09:39Z alex $
 */
/*********************************************************/
/*  This unit initializes the backend given backend URI  */
/*********************************************************/

#include <errno.h>
#include <string.h>
#include <stdbool.h>
#include <galerautils.h>
#include "gcs_backend.h"

#include "gcs_dummy.h"
#ifdef    GCS_USE_SPREAD
#include "gcs_spread.h"
#endif /* GCS_USE_SPREAD */
#ifdef    GCS_USE_VS
#include "gcs_vs.h"
#endif /* GCS_USE_VS */
#ifdef    GCS_USE_GCOMM
#include "gcs_gcomm.h"
#endif /* GCS_USE_GCOMM */

/* Static array describing backend ID - open() pairs */
static
struct {
    const char* id;
    gcs_backend_create_t create;
}
    const backend[] =
    {
#ifdef    GCS_USE_GCOMM
        { "gcomm", gcs_gcomm_create},
#endif /* GCS_USE_GCOMM */
#ifdef    GCS_USE_VS
        { "vsbes", gcs_vs_create },
#endif /* GCS_USE_VS */
#ifdef    GCS_USE_SPREAD
        { "spread", gcs_spread_create },
#endif /* GCS_USE_SPREAD */
        { "dummy", gcs_dummy_create },
        { NULL, NULL } // terminating pair
    };

static const char backend_sep[] = "://";

/* Returns true if backend matches, false otherwise */
static bool
backend_type_is (const char* uri, const char* type, const size_t len)
{
    if (len == strlen(type)) {
        if (!strncmp (uri, type, len)) return true;
    }
    return false;
}

long
gcs_backend_init (gcs_backend_t* const bk,
		  const char*    const uri,
		  gu_config_t*   const conf)
{
    char* sep;

    assert (NULL != bk);
    assert (NULL != uri);

    sep = strstr (uri, backend_sep);

    if (NULL != sep) {
        size_t type_len  = sep - uri;
        const char* addr = sep + strlen(backend_sep);
        long i;
        /* try to match any of specified backends */
        for (i = 0; backend[i].id != NULL; i++) {
            if (backend_type_is (uri, backend[i].id, type_len))
                return backend[i].create (bk, addr, conf);
        }

        /* no backends matched */
        gu_error ("Backend not supported: %s", uri);
        return -ESOCKTNOSUPPORT;
    }

    gu_error ("Invalid backend URI: %s", uri);
    return -EINVAL;
}

