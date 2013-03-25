/*
 * Copyright (C) 2009 Codership Oy <info@codership.com>
 *
 * $Id$
 */

/*!
 * @file Input map for EVS messaging. Provides simple interface for
 *       handling messages with different safety guarantees.
 *
 * @note When operating with iterators, note that evs::Message
 *       accessed through iterator may have different sequence
 *       number as it position dictates. Use sequence number
 *       found from key part.
 *
 * @todo Fix issue in above note if feasible.
 */

#ifndef EVS_INPUT_MAP2_HPP
#define EVS_INPUT_MAP2_HPP

#include "gu_datagram.hpp"

#include "evs_message2.hpp"
#include "gcomm/map.hpp"

#include <boost/pool/pool_alloc.hpp>

#include <vector>



namespace gcomm
{
    /* Forward declarations */
    class InputMapMsgKey;
    std::ostream& operator<<(std::ostream&, const InputMapMsgKey&);
    namespace evs
    {
        class InputMapMsg;
        std::ostream& operator<<(std::ostream&, const InputMapMsg&);
        class InputMapMsgIndex;
        class InputMapNode;
        std::ostream& operator<<(std::ostream&, const InputMapNode&);
        typedef std::vector<InputMapNode> InputMapNodeIndex;
        std::ostream& operator<<(std::ostream&, const InputMapNodeIndex&);
        class InputMap;
    }
}

/* Internal msg representation */
class gcomm::InputMapMsgKey
{
public:
    InputMapMsgKey(const size_t index, const evs::seqno_t seq) :
        index_ (index),
        seq_   (seq)
    { }

    size_t       get_index() const { return index_; }
    evs::seqno_t get_seq  () const { return seq_;   }

    bool operator<(const InputMapMsgKey& cmp) const
    {
        return (seq_ < cmp.seq_ || (seq_ == cmp.seq_ && index_ < cmp.index_));
    }

private:
    size_t       const index_;
    evs::seqno_t const seq_;
};



/* Internal message representation */
class gcomm::evs::InputMapMsg
{
public:
    InputMapMsg(const UserMessage&       msg_,
                const gu::Datagram& rb_   ) :
        msg  (msg_ ),
        rb   (rb_  )
    { }

    InputMapMsg(const InputMapMsg& m) :
        msg  (m.msg ),
        rb   (m.rb  )
    { }

    ~InputMapMsg() { }

    const UserMessage& get_msg () const { return msg;  }
    const gu::Datagram&    get_rb  () const { return rb;   }
private:
    void operator=(const InputMapMsg&);

    UserMessage const msg;
    gu::Datagram rb;
};


#if 1

class DummyMutex
{
public:
    void lock() { }
    void unlock() {}
};

class gcomm::evs::InputMapMsgIndex :
    public Map<InputMapMsgKey, InputMapMsg,
               std::map<InputMapMsgKey,
                        InputMapMsg,
                        std::less<InputMapMsgKey>,
                        boost::fast_pool_allocator<
                            std::pair<const InputMapMsgKey, InputMapMsg>,
                            boost::default_user_allocator_new_delete,
                            DummyMutex> > >
{ };
#else

class gcomm::evs::InputMapMsgIndex :
    public Map<InputMapMsgKey, InputMapMsg> { };
//               std::map<InputMapMsgKey,
//                        InputMapMsg,
//                        std::less<InputMapMsgKey>,
//                        boost::fast_pool_allocator<
//                            std::pair<const InputMapMsgKey, InputMapMsg> > > >
#endif // 0

/* Internal node representation */
class gcomm::evs::InputMapNode
{
public:
    InputMapNode() : idx_(), range_(0, -1), safe_seq_(-1) { }

    void   set_range     (const Range   r)       { range_     = r; }
    void   set_safe_seq  (const seqno_t s)       { safe_seq_  = s; }
    void   set_index     (const size_t  i)       { idx_       = i; }

    Range   get_range     ()               const { return range_;     }
    seqno_t get_safe_seq  ()               const { return safe_seq_;  }
    size_t  get_index     ()               const { return idx_;       }

private:
    size_t  idx_;
    Range   range_;
    seqno_t safe_seq_;
};





/*!
 * Input map for messages.
 *
 */
class gcomm::evs::InputMap
{
public:

    /* Iterators exposed to user */
    typedef InputMapMsgIndex::iterator iterator;
    typedef InputMapMsgIndex::const_iterator const_iterator;

    /*!
     * Default constructor.
     */
    InputMap();

    /*!
     * Default destructor.
     */
    ~InputMap();

    /*!
     * Get current value of aru_seq.
     *
     * @return Current value of aru_seq
     */
    seqno_t get_aru_seq () const { return aru_seq_;  }

    /*!
     * Get current value of safe_seq.
     *
     * @return Current value of safe_seq
     */
    seqno_t get_safe_seq() const { return safe_seq_; }

    /*!
     * Set sequence number safe for node.
     *
     * @param uuid Node uuid
     * @param seq Sequence number to be set safe
     *
     * @throws FatalException if node was not found or sequence number
     *         was not in the allowed range
     */
    void  set_safe_seq(const size_t uuid, const seqno_t seq)
        throw (gu::Exception);

    /*!
     * Get current value of safe_seq for node.
     *
     * @param uuid Node uuid
     *
     * @return Safe sequence number for node
     *
     * @throws FatalException if node was not found
     */
    seqno_t get_safe_seq(const size_t uuid) const
        throw (gu::Exception)
    {
        return node_index_->at(uuid).get_safe_seq();
    }

    /*!
     * Get current range parameter for node
     *
     * @param uuid Node uuid
     *
     * @return Range parameter for node
     *
     * @throws FatalException if node was not found
     */
    Range get_range   (const size_t uuid) const
        throw (gu::Exception)
    {
        return node_index_->at(uuid).get_range();
    }

    seqno_t get_min_hs() const
        throw (gu::Exception);

    seqno_t get_max_hs() const
        throw (gu::Exception);

    /*!
     * Get iterator to the beginning of the input map
     *
     * @return Iterator pointing to the first element
     */
    iterator begin() const { return msg_index_->begin(); }

    /*!
     * Get iterator next to the last element of the input map
     *
     * @return Iterator pointing past the last element
     */
    iterator end  () const { return msg_index_->end(); }

    /*!
     * Check if message pointed by iterator fulfills O_SAFE condition.
     *
     * @return True or false
     */
    bool is_safe  (iterator i) const
        throw (gu::Exception)
    {
        const seqno_t seq(InputMapMsgIndex::get_key(i).get_seq());
        return (seq <= safe_seq_);
    }

    /*!
     * Check if message pointed by iterator fulfills O_AGREED condition.
     *
     * @return True or false
     */
    bool is_agreed(iterator i) const
        throw (gu::Exception)
    {
        const seqno_t seq(InputMapMsgIndex::get_key(i).get_seq());
        return (seq <= aru_seq_);
    }

    /*!
     * Check if message pointed by iterator fulfills O_FIFO condition.
     *
     * @return True or false
     */
    bool is_fifo  (iterator i) const
        throw (gu::Exception)
    {
        const seqno_t seq(InputMapMsgIndex::get_key(i).get_seq());
        const InputMapNode& node((*node_index_)[
                                     InputMapMsgIndex::get_key(i).get_index()]);
        return (node.get_range().get_lu() > seq);
    }

    bool has_deliverables() const
    {
        if (msg_index_->empty() == false)
        {
            if (n_msgs_[O_FIFO] > 0 && is_fifo(msg_index_->begin()))
                return true;
            else if (n_msgs_[O_AGREED] > 0 && is_agreed(msg_index_->begin()))
                return true;
            else if (n_msgs_[O_SAFE] > 0 && is_safe(msg_index_->begin()))
                return true;
            else if (n_msgs_[O_DROP] > max_droppable_)
                return true;
            return false;
        }
        else
        {
            return false;
        }
    }

    /*!
     * Insert new message into input map.
     *
     * @param uuid   Node uuid of the message source
     * @param msg    EVS message
     * @param rb     ReadBuf pointer associated to message
     * @param offset Offset to the beginning of the payload
     *
     * @return Range parameter of the node
     *
     * @throws FatalException if node not found or message sequence
     *         number is out of allowed range
     */
    Range insert(const size_t uuid, const UserMessage& msg,
                 const gu::Datagram& dg = gu::Datagram())
        throw (gu::Exception);

    /*!
     * Erase message pointed by iterator. Note that message may still
     * be recovered through recover() method as long as it does not
     * fulfill O_SAFE constraint.
     *
     * @param i Iterator
     *
     * @throws FatalException if iterator is not valid
     */
    void erase(iterator i)
        throw (gu::Exception);

    /*!
     * Find message.
     *
     * @param uuid Message source node uuid
     * @param seq  Message sequence numeber
     *
     * @return Iterator pointing to message or at end() if message was not found
     *
     * @throws FatalException if node was not found
     */
    iterator find(const size_t uuid, const seqno_t seq) const
        throw (gu::Exception);

    /*!
     * Recover message.
     *
     * @param uuid Message source node uuid
     * @param seq  Message sequence number
     *
     * @return Iterator pointing to the message
     *
     * @throws FatalException if node or message was not found
     */
    iterator recover(const size_t uuid, const seqno_t seq) const
        throw (gu::Exception);

    /*!
     *
     */
    void reset(const size_t, const seqno_t = 256)
        throw (gu::Exception);

    /*!
     * Clear input map state.
     */
    void clear();


private:
    friend std::ostream& operator<<(std::ostream&, const InputMap&);
    /* Non-copyable */
    InputMap(const InputMap&);
    void operator=(const InputMap&);

    /*!
     * Update aru_seq value to represent current state.
     */
    void update_aru()
        throw (gu::Exception);

    /*!
     * Clean up recovery index. All messages up to safe_seq are removed.
     */
    void cleanup_recovery_index()
        throw (gu::Exception);

    seqno_t            window_;
    seqno_t            safe_seq_;       /*!< Safe seqno              */
    seqno_t            aru_seq_;        /*!< All received upto seqno */
    InputMapNodeIndex* node_index_;     /*!< Index of nodes          */
    InputMapMsgIndex*  msg_index_;      /*!< Index of messages       */
    InputMapMsgIndex*  recovery_index_; /*!< Recovery index          */

    std::vector<size_t> n_msgs_;
    size_t max_droppable_;
};

#endif // EVS_INPUT_MAP2_HPP
