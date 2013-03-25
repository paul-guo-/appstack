/*
 * Copyright (C) 2010-2011 Codership Oy <info@codership.com>
 */

/*! @file mem store class */

#ifndef _gcache_mem_store_hpp_
#define _gcache_mem_store_hpp_

#include "gcache_memops.hpp"
#include "gcache_fd.hpp"
#include "gcache_mmap.hpp"
#include "gcache_bh.hpp"

#include <string>
#include <set>

namespace gcache
{
    class MemStore : public MemOps
    {
        typedef std::map<int64_t, const void*> seqno2ptr_t;
        typedef seqno2ptr_t::iterator          seqno2ptr_iter_t;

    public:

        MemStore (ssize_t max_size, seqno2ptr_t& seqno2ptr) throw ()
            : max_size_ (max_size),
              size_     (0),
              allocd_   (),
              seqno2ptr_(seqno2ptr)
        {}

        void reset () throw ()
        {
            for (std::set<void*>::iterator buf(allocd_.begin());
                 buf != allocd_.end(); ++buf)
            {
                ::free (*buf);
            }

            allocd_.clear();
            size_ = 0;
        }

        ~MemStore () { reset(); }

        void* malloc  (ssize_t size) throw ()
        {
            if (size > max_size_ || have_free_space(size) == false) return 0;

            assert (size_ + size <= max_size_);

            BufferHeader* bh (BH_cast (::malloc (size)));

            if (gu_likely(0 != bh))
            {
                allocd_.insert(bh);

                bh->size    = size;
                bh->seqno_g = SEQNO_NONE;
                bh->seqno_d = SEQNO_ILL;
                bh->flags   = 0;
                bh->store   = BUFFER_IN_MEM;
                bh->ctx     = this;

                size_ += size;

                return (bh + 1);
            }

            return 0;
        }

        void  free (const void* ptr)  throw()
        {
            if (gu_likely (0 != ptr))
            {
                BufferHeader* const bh(ptr2BH(ptr));

                assert(bh->size > 0);
                assert(bh->size <= size_);
                assert(bh->store == BUFFER_IN_MEM);
                assert(bh->ctx == this);

                BH_release (bh);
                if (SEQNO_NONE == bh->seqno_g) discard (bh);
            }
        }

        void* realloc (void* ptr, ssize_t size) throw ()
        {
            BufferHeader* bh(0);
            ssize_t old_size(0);

            if (ptr)
            {
                bh = ptr2BH(ptr);
                assert (SEQNO_NONE == bh->seqno_g);
                old_size = bh->size;
            }

            ssize_t const diff_size(size - old_size);

            if (size > max_size_ ||
                have_free_space(diff_size) == false) return 0;

            assert (size_ + diff_size <= max_size_);

            void* tmp = ::realloc (bh, size);

            if (tmp)
            {
                allocd_.erase(bh);
                allocd_.insert(tmp);

                bh = BH_cast(tmp);
                assert (bh->size == old_size);
                bh->size  = size;

                size_ += diff_size;

                return (bh + 1);
            }

            return 0;
        }

        void discard (BufferHeader* bh) throw ()
        {
            assert (BH_is_released(bh));

            size_ -= bh->size;
            ::free (bh);
            allocd_.erase(bh);
        }

        void set_max_size (ssize_t size) throw() { max_size_ = size; }

        void seqno_reset();

        // for unit tests only
        ssize_t _allocd () const throw() { return size_; }

    private:

        bool have_free_space (ssize_t size) throw();

        ssize_t         max_size_;
        ssize_t         size_;
        std::set<void*> allocd_;
        seqno2ptr_t&    seqno2ptr_;
    };
}

#endif /* _gcache_mem_store_hpp_ */

