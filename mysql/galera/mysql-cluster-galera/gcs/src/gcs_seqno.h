/*
 * Copyright (C) 2008-2012 Codership Oy <info@codership.com>
 *
 * $Id: gcs_seqno.h 2830 2012-06-23 12:49:47Z alex $
 */
/*
 *  Operations on seqno.
 */

#ifndef _gcs_seqno_h_
#define _gcs_seqno_h_

#include "galerautils.h"
#include "gcs.h"

#define gcs_seqno_le(x) ((gcs_seqno_t)gu_le64(x))
#define gcs_seqno_be(x) ((gcs_seqno_t)gu_be64(x))

#define gcs_seqno_htog(x) ((gcs_seqno_t)htog64(x))
#define gcs_seqno_gtoh gcs_seqno_htog

#endif /* _gcs_seqno_h_ */
