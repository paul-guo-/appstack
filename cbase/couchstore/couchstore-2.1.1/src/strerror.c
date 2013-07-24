/* -*- Mode: C; tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
#include "config.h"
#include <stdlib.h>
#include <libcouchstore/couch_db.h>

LIBCOUCHSTORE_API
const char *couchstore_strerror(couchstore_error_t errcode)
{
    switch (errcode) {
    case COUCHSTORE_SUCCESS:
        return "success";
    case COUCHSTORE_ERROR_OPEN_FILE:
        return "error opening file";
    case COUCHSTORE_ERROR_CORRUPT:
        return "malformed data in file";
    case COUCHSTORE_ERROR_ALLOC_FAIL:
        return "failed to allocate buffer";
    case COUCHSTORE_ERROR_READ:
        return "error reading file";
    case COUCHSTORE_ERROR_DOC_NOT_FOUND:
        return "document not found";
    case COUCHSTORE_ERROR_NO_HEADER:
        return "no header in non-empty file";
    case COUCHSTORE_ERROR_WRITE:
        return "error writing to file";
    case COUCHSTORE_ERROR_HEADER_VERSION:
        return "incorrect version in header";
    case COUCHSTORE_ERROR_CHECKSUM_FAIL:
        return "checksum fail";
    case COUCHSTORE_ERROR_INVALID_ARGUMENTS:
        return "invalid arguments";
    case COUCHSTORE_ERROR_NO_SUCH_FILE:
        return "no such file";
    default:
        return NULL;
    }
}
