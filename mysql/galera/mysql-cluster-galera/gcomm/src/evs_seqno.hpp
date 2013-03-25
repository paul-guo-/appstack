/*
 * Copyright (C) 2009 Codership Oy <info@codership.com>
 */

#ifndef EVS_SEQNO_HPP
#define EVS_SEQNO_HPP

#include "gcomm/types.hpp"

#include <stdint.h> // for uint16_t
#include <ostream>
#include <cassert>

namespace gcomm
{
    namespace evs
    {
        typedef int64_t seqno_t;
        
        class Range;
        std::ostream& operator<<(std::ostream&, const Range&);
    }
}


/*!
 *
 */
class gcomm::evs::Range
{
public:
    Range(const seqno_t lu = -1, const seqno_t hs = -1) :
        lu_(lu),
        hs_(hs)
    {}
    seqno_t get_lu() const { return lu_; }
    seqno_t get_hs() const { return hs_; }
    
    void set_lu(const seqno_t s) { lu_ = s; }
    void set_hs(const seqno_t s) { hs_ = s; }
    
    size_t serialize(gu::byte_t* buf, size_t buflen, size_t offset) const
    {
        gu_trace(offset = gcomm::serialize(lu_, buf, buflen, offset));
        gu_trace(offset = gcomm::serialize(hs_, buf, buflen, offset));
        return offset;
    }
    
    size_t unserialize(const gu::byte_t* buf, size_t buflen, size_t offset)
    {
        gu_trace(offset = gcomm::unserialize(buf, buflen, offset, &lu_));
        gu_trace(offset = gcomm::unserialize(buf, buflen, offset, &hs_));
        return offset;
    }
    
    static size_t serial_size()
    {
        return 2 * gcomm::serial_size(seqno_t());
    }

    bool operator==(const Range& cmp) const
    {
        return (lu_ == cmp.lu_ && hs_ == cmp.hs_);
    }

private:
    seqno_t lu_; /*!< Lowest unseen seqno */
    seqno_t hs_; /*!< Highest seen seqno  */
};

inline std::ostream& gcomm::evs::operator<<(std::ostream& os, const gcomm::evs::Range& r)
{
    return (os << "[" << r.get_lu() << "," << r.get_hs() << "]");
}

#endif // EVS_SEQNO_HPP
