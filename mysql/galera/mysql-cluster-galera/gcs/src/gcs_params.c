/*
 * Copyright (C) 2010-2012 Codership Oy <info@codership.com>
 *
 * $Id: gcs_params.c 2779 2012-05-08 20:09:15Z alex $
 */

#include "gcs_params.h"

#include <inttypes.h>
#include <errno.h>

const char* const GCS_PARAMS_FC_FACTOR         = "gcs.fc_factor";
const char* const GCS_PARAMS_FC_LIMIT          = "gcs.fc_limit";
const char* const GCS_PARAMS_FC_MASTER_SLAVE   = "gcs.fc_master_slave";
const char* const GCS_PARAMS_FC_DEBUG          = "gcs.fc_debug";
const char* const GCS_PARAMS_SYNC_DONOR        = "gcs.sync_donor";
const char* const GCS_PARAMS_MAX_PKT_SIZE      = "gcs.max_packet_size";
const char* const GCS_PARAMS_RECV_Q_HARD_LIMIT = "gcs.recv_q_hard_limit";
const char* const GCS_PARAMS_RECV_Q_SOFT_LIMIT = "gcs.recv_q_soft_limit";
const char* const GCS_PARAMS_MAX_THROTTLE      = "gcs.max_throttle";

static double  const GCS_PARAMS_DEFAULT_FC_FACTOR         = 0.5;
static long    const GCS_PARAMS_DEFAULT_FC_LIMIT          = 16;
static bool    const GCS_PARAMS_DEFAULT_FC_MASTER_SLAVE   = false;
static long    const GCS_PARAMS_DEFAULT_FC_DEBUG          = 0;
static bool    const GCS_PARAMS_DEFAULT_SYNC_DONOR        = false;
static long    const GCS_PARAMS_DEFAULT_MAX_PKT_SIZE      = 64500;
static ssize_t const GCS_PARAMS_DEFAULT_RECV_Q_HARD_LIMIT = SSIZE_MAX;
static double  const GCS_PARAMS_DEFAULT_RECV_Q_SOFT_LIMIT = 0.25;
static double  const GCS_PARAMS_DEFAULT_MAX_THROTTLE      = 0.25;

static long
params_init_bool (gu_config_t* conf, const char* const name,
                  bool const def_val, bool* const var)
{
    bool val;

    long rc = gu_config_get_bool(conf, name, &val);

    if (rc < 0) {
        /* Cannot parse parameter value */
        gu_error ("Bad %s value", name);
        return rc;
    }
    else if (rc > 0) {
        /* Parameter value not set, use default */
        val = def_val;
        gu_config_set_bool (conf, name, val);
    }

    *var = val;

    return 0;
}

static long
params_init_long (gu_config_t* conf, const char* const name,
                  long const def_val, long min_val, long max_val,
                  long* const var)
{
    int64_t val;

    long rc = gu_config_get_int64(conf, name, &val);

    if (rc < 0) {
        /* Cannot parse parameter value */
        gu_error ("Bad %s value", name);
        return rc;
    }
    else if (rc > 0) {
        /* Parameter value not set, use default */
        val = def_val;
        gu_config_set_int64 (conf, name, val);
    }
    else {
        /* Found parameter value */
        if (max_val == min_val) {
            max_val = LONG_MAX;
            min_val = LONG_MIN;
        }

        if (val < min_val || val > max_val) {
            gu_error ("%s value out of range [%ld, %ld]: %"PRIi64,
                      name, min_val, max_val, val);
            return -EINVAL;
        }
    }

    *var = val;

    return 0;
}

static long
params_init_int64 (gu_config_t* conf, const char* const name,
                   int64_t const def_val, int64_t const min_val,
                   int64_t const max_val, int64_t* const var)
{
    int64_t val;

    long rc = gu_config_get_int64(conf, name, &val);

    if (rc < 0) {
        /* Cannot parse parameter value */
        gu_error ("Bad %s value", name);
        return rc;
    }
    else if (rc > 0) {
        /* Parameter value not set, use default */
        val = def_val;
        gu_config_set_int64 (conf, name, val);
    }
    else {
        /* Found parameter value */
        if ((min_val != max_val) && (val < min_val || val > max_val)) {
            gu_error ("%s value out of range [%"PRIi64", %"PRIi64"]: %"PRIi64,
                      name, min_val, max_val, val);
            return -EINVAL;
        }
    }

    *var = val;

    return 0;
}

static long
params_init_double (gu_config_t* conf, const char* const name,
                    double const def_val, double const min_val,
                    double const max_val, double* const var)
{
    double val;

    long rc = gu_config_get_double(conf, name, &val);

    if (rc < 0) {
        /* Cannot parse parameter value */
        gu_error ("Bad %s value", name);
        return rc;
    }
    else if (rc > 0) {
        /* Parameter value not set, use default */
        val = def_val;
        gu_config_set_double (conf, name, val);
    }
    else {
        /* Found parameter value */
        if ((min_val != max_val) && (val < min_val || val > max_val)) {
            gu_error ("%s value out of range [%f, %f]: %f",
                      name, min_val, max_val, val);
            return -EINVAL;
        }
    }

    *var = val;

    return 0;
}

long
gcs_params_init (struct gcs_params* params, gu_config_t* config)
{
    long ret;

    if ((ret = params_init_long (config, GCS_PARAMS_FC_LIMIT,
                                 GCS_PARAMS_DEFAULT_FC_LIMIT, 0, LONG_MAX,
                                 &params->fc_base_limit))) return ret;

    if ((ret = params_init_long (config, GCS_PARAMS_FC_DEBUG,
                                 GCS_PARAMS_DEFAULT_FC_DEBUG, 0, LONG_MAX,
                                 &params->fc_debug))) return ret;

    if ((ret = params_init_long (config, GCS_PARAMS_MAX_PKT_SIZE,
                                 GCS_PARAMS_DEFAULT_MAX_PKT_SIZE,0,LONG_MAX,
                                 &params->max_packet_size))) return ret;

    if ((ret = params_init_double (config, GCS_PARAMS_FC_FACTOR,
                                   GCS_PARAMS_DEFAULT_FC_FACTOR, 0.0, 1.0,
                                   &params->fc_resume_factor))) return ret;

    if ((ret = params_init_double (config, GCS_PARAMS_RECV_Q_SOFT_LIMIT,
                                   GCS_PARAMS_DEFAULT_RECV_Q_SOFT_LIMIT,
                                   0.0, 1.0 - 1.e-9,
                                   &params->recv_q_soft_limit))) return ret;

    if ((ret = params_init_double (config, GCS_PARAMS_MAX_THROTTLE,
                                   GCS_PARAMS_DEFAULT_MAX_THROTTLE,
                                   0.0, 1.0 - 1.e-9,
                                   &params->max_throttle))) return ret;

    int64_t tmp;
    if ((ret = params_init_int64 (config, GCS_PARAMS_RECV_Q_HARD_LIMIT,
                                  GCS_PARAMS_DEFAULT_RECV_Q_HARD_LIMIT, 0, 0,
                                  &tmp))) return ret;
    params->recv_q_hard_limit = tmp * 0.9; // allow for some meta overhead

    if ((ret = params_init_bool (config, GCS_PARAMS_FC_MASTER_SLAVE,
                                 GCS_PARAMS_DEFAULT_FC_MASTER_SLAVE,
                                 &params->fc_master_slave))) return ret;

    if ((ret = params_init_bool (config, GCS_PARAMS_SYNC_DONOR,
                                 GCS_PARAMS_DEFAULT_SYNC_DONOR,
                                 &params->sync_donor))) return ret;
    return 0;
}
