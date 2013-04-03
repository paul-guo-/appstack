/* Copyright (C) 2011 Codership Oy <info@codership.com> */

#include "garb_gcs.hpp"

namespace garb
{

static int const REPL_PROTO_VER(127);
static int const APPL_PROTO_VER(127);

Gcs::Gcs (gu::Config&        gconf,
          const std::string& address,
          const std::string& group) throw (gu::Exception)
:
    closed_ (true),
    gcs_ (gcs_create (reinterpret_cast<gu_config_t*>(&gconf), NULL,
                      GCS_ARBITRATOR_NAME, "", REPL_PROTO_VER, APPL_PROTO_VER))
{
    if (!gcs_)
    {
        gu_throw_fatal << "Failed to create GCS object";
    }

    ssize_t ret = gcs_open (gcs_, group.c_str(), address.c_str());

    if (ret < 0)
    {
        gcs_destroy (gcs_);
        gu_throw_error(-ret) << "Failed to open connection to group";
    }

    closed_ = false;
}

Gcs::~Gcs ()
{
    if (!closed_)
    {
        log_warn << "Destroying non-closed object, bad idea";
        close ();
    }

    gcs_destroy (gcs_);
}

void
Gcs::recv (gcs_action& act) throw (gu::Exception)
{
again:
    ssize_t ret = gcs_recv(gcs_, &act);

    if (gu_unlikely(ret < 0))
    {
        if (-ECANCELED == ret)
        {
            ret = gcs_resume_recv (gcs_);
            if (0 == ret) goto again;
        }

        log_fatal << "Receiving from group failed: " << ret
                  << " (" << strerror(-ret) << ")";
        gu_throw_error(-ret) << "Receiving from group failed";
    }
}

void
Gcs::request_state_transfer (const std::string& request,
                             const std::string& donor) throw (gu::Exception)
{
    gcs_seqno_t order;

    log_info << "Sending state transfer request: '" << request
             << "', size: " << request.length();

    /* Need to substitute the first ':' for \0 */

    ssize_t req_len = request.length() + 1 /* \0 */;
    char* const req_str(reinterpret_cast<char*>(::malloc(
                        req_len + 1 /* potentially need one more \0 */)));

    if (!req_str)
    {
        gu_throw_error (ENOMEM) << "Cannot allocate " << req_len
                                << " bytes for state transfer request";
    }

    ::strcpy(req_str, request.c_str());
    char* column_ptr = ::strchr(req_str, ':');

    if (column_ptr)
    {
        *column_ptr = '\0';
    }
    else /* append an empty string */
    {
        req_str[req_len] = '\0';
        req_len++;
    }

    ssize_t ret;
    do
    {
        ret = gcs_request_state_transfer (gcs_, req_str, req_len, donor.c_str(),
                                          &order);
    }
    while (-EAGAIN == ret && (usleep(1000000), true));

    free (req_str);

    if (ret < 0)
    {
        log_fatal << "State transfer request failed: " << ret
                  << " (" << strerror(-ret) << ")";
        gu_throw_error(-ret) << "State transfer request failed";
    }
}

void
Gcs::join (gcs_seqno_t seqno) throw (gu::Exception)
{
    ssize_t ret = gcs_join (gcs_, seqno);

    if (ret < 0)
    {
        log_fatal << "Joining group failed: " << ret
                  << " (" << strerror(-ret) << ")";
        gu_throw_error(-ret) << "Joining group failed";
    }
}

void
Gcs::set_last_applied (gcs_seqno_t seqno) throw()
{
    (void) gcs_set_last_applied(gcs_, seqno);
}

void
Gcs::close ()
{
    if (!closed_)
    {
        ssize_t ret = gcs_close (gcs_);

        if (ret < 0)
        {
            log_error << "Failed to close connection to group";
        }
        else
        {
            closed_ = true;
        }
    }
    else
    {
        log_warn << "Attempt to close a closed connection";
    }
}

} /* namespace garb */
