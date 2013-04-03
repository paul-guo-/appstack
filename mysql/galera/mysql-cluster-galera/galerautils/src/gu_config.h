// Copyright (C) 2010 Codership Oy <info@codership.com>

/**
 * @file
 * C-interface for configuration management
 *
 * $Id: gu_config.h 2887 2012-10-24 16:32:16Z alex $
 */

#ifndef _gu_config_h_
#define _gu_config_h_

#include <stdint.h>
#include <unistd.h> // for ssize_t

#ifdef __cplusplus
extern "C" {
#endif

typedef struct gu_config gu_config_t;

gu_config_t*
gu_config_create (const char* params);

void
gu_config_destroy (gu_config_t* cnf);

/* Getters return 0 on success, 1 when key not found, negative error code
 * in case of other errors (conversion failed and such) */

long
gu_config_get_string (gu_config_t* cnf, const char* key, const char** val);

long
gu_config_get_int64  (gu_config_t* cnf, const char* key, int64_t* val);

long
gu_config_get_double (gu_config_t* cnf, const char* key, double* val);

long
gu_config_get_ptr    (gu_config_t* cnf, const char* key, void** val);

long
gu_config_get_bool   (gu_config_t* cnf, const char* key, bool* val);

void
gu_config_set_string (gu_config_t* cnf, const char* key, const char* val);

void
gu_config_set_int64  (gu_config_t* cnf, const char* key, int64_t val);

void
gu_config_set_double (gu_config_t* cnf, const char* key, double val);

void
gu_config_set_ptr    (gu_config_t* cnf, const char* key, const void* val);

void
gu_config_set_bool   (gu_config_t* cnf, const char* key, bool val);

ssize_t
gu_config_print      (gu_config_t* cnf, char* buf, ssize_t buf_len);

#ifdef __cplusplus
}
#endif

#endif /* _gu_config_h_ */

