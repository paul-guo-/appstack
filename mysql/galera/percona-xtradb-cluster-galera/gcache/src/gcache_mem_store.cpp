/*
 * Copyright (C) 2010-2011 Codership Oy <info@codership.com>
 */

#include "gcache_mem_store.hpp"

namespace gcache
{

bool
MemStore::have_free_space (ssize_t size) throw()
{
    while ((size_ + size > max_size_) && !seqno2ptr_.empty())
    {
        /* try to free some released bufs */
        seqno2ptr_iter_t const i  (seqno2ptr_.begin());
        BufferHeader*    const bh (ptr2BH (i->second));

        if (BH_is_released(bh)) /* discard buffer */
        {
            seqno2ptr_.erase(i);
            bh->seqno_g = SEQNO_NONE;

            switch (bh->store)
            {
            case BUFFER_IN_RB:
                bh->ctx->discard(bh);
                break;
            case BUFFER_IN_MEM:
                discard(bh);
                break;
            }
        }
    }

    return (size_ + size <= max_size_);
}

void
MemStore::seqno_reset()
{
    for (std::set<void*>::iterator buf(allocd_.begin()); buf != allocd_.end();)
    {
        std::set<void*>::iterator tmp(buf); ++buf;

        BufferHeader* const bh(ptr2BH(*tmp));

        if (bh->seqno_g != SEQNO_NONE)
        {
            assert (BH_is_released(bh));

            size_ -= bh->size;
            ::free (bh);
            allocd_.erase (tmp);
        }
    }
}

} /* namespace gcache */
