/* -*- Mode: C++; tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
#ifndef QUEUEDITEM_HH
#define QUEUEDITEM_HH 1

#include "common.hh"
#include "item.hh"
#include "stats.hh"

enum queue_operation {
    queue_op_set,
    queue_op_del,
    queue_op_flush,
    queue_op_empty,
    queue_op_commit,
    queue_op_checkpoint_start,
    queue_op_checkpoint_end,
    queue_op_online_update_start,
    queue_op_online_update_end,
    queue_op_online_update_revert
};

typedef enum {
    vbucket_del_success,
    vbucket_del_fail,
    vbucket_del_invalid
} vbucket_del_result;

/**
 * Representation of an item queued for persistence or tap.
 */
class QueuedItem : public RCValue {
public:
    QueuedItem(const std::string &k, const uint16_t vb,
               enum queue_operation o, const uint16_t vb_version = -1,
               const int64_t rid = -1)
        : key(k), rowId(rid), queued(ep_current_time()),
          op(o), vbucket(vb), vbucketVersion(vb_version)
    {
        ObjectRegistry::onCreateQueuedItem(this);
    }

    ~QueuedItem() {
        ObjectRegistry::onDeleteQueuedItem(this);
    }

    const std::string &getKey(void) const { return key; }
    uint16_t getVBucketId(void) const { return vbucket; }
    uint16_t getVBucketVersion(void) const { return vbucketVersion; }
    uint32_t getQueuedTime(void) const { return queued; }
    enum queue_operation getOperation(void) const { return op; }
    int64_t getRowId() const { return rowId; }

    void setQueuedTime(uint32_t queued_time) {
        queued = queued_time;
    }

    void setOperation(enum queue_operation o) {
        op = o;
    }

    bool operator <(const QueuedItem &other) const {
        return getVBucketId() == other.getVBucketId() ?
            getKey() < other.getKey() : getVBucketId() < other.getVBucketId();
    }

    size_t size() {
        return sizeof(QueuedItem) + getKey().size();
    }

private:
    std::string key;
    int64_t  rowId;
    uint32_t queued;
    enum queue_operation op;
    uint16_t vbucket;
    uint16_t vbucketVersion;

    DISALLOW_COPY_AND_ASSIGN(QueuedItem);
};

typedef RCPtr<QueuedItem> queued_item;

/**
 * Order QueuedItem objects pointed by shared_ptr by their keys.
 */
class CompareQueuedItemsByKey {
public:
    CompareQueuedItemsByKey() {}
    bool operator()(const queued_item &i1, const queued_item &i2) {
        return i1->getKey() < i2->getKey();
    }
};

/**
 * Order QueuedItem objects by their row ids.
 */
class CompareQueuedItemsByRowId {
public:
    CompareQueuedItemsByRowId() {}
    bool operator()(const queued_item &i1, const queued_item &i2) {
        return i1->getRowId() < i2->getRowId();
    }
};

/**
 * Order QueuedItem objects by their vbucket then row ids.
 */
class CompareQueuedItemsByVBAndRowId {
public:
    CompareQueuedItemsByVBAndRowId() {}
    bool operator()(const queued_item &i1, const queued_item &i2) {
        return i1->getVBucketId() == i2->getVBucketId()
            ? i1->getRowId() < i2->getRowId()
            : i1->getVBucketId() < i2->getVBucketId();
    }
};

/**
 * Compare two Schwartzian-transformed QueuedItems.
 */
template <typename T>
class TaggedQueuedItemComparator {
public:
    TaggedQueuedItemComparator() {}

    bool operator()(std::pair<T, queued_item> i1, std::pair<T, queued_item> i2) {
        return (i1.first == i2.first)
            ? (i1.second->getRowId() < i2.second->getRowId())
            : (i1 < i2);
    }
};

#endif /* QUEUEDITEM_HH */
