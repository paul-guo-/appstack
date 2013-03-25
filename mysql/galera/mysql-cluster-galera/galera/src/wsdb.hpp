//
// Copyright (C) 2010 Codership Oy <info@codership.com>
//
#ifndef GALERA_WSDB_HPP
#define GALERA_WSDB_HPP

#include "trx_handle.hpp"
#include "wsrep_api.h"
#include "gu_unordered.hpp"

namespace galera
{
    class Wsdb
    {

        class Conn
        {
        public:
            Conn(wsrep_conn_id_t conn_id)
                :
                conn_id_(conn_id),
                trx_(0)
            { }

            Conn(const Conn& other)
                :
                conn_id_(other.conn_id_),
                trx_(other.trx_)
            { }

            ~Conn() { if (trx_ != 0) trx_->unref(); }

            void assign_trx(TrxHandle* trx)
            {
                if (trx_ != 0) trx_->unref();
                trx_ = trx;
            }

            TrxHandle* get_trx()
            {
                return trx_;
            }

        private:
            void operator=(const Conn&);
            wsrep_conn_id_t conn_id_;
            TrxHandle* trx_;
        };


        class TrxHash
        {
        public:
            size_t operator()(const wsrep_trx_id_t& key) const { return key; }
        };

        typedef gu::UnorderedMap<wsrep_trx_id_t, TrxHandle*, TrxHash> TrxMap;

        class ConnHash
        {
        public:
            size_t operator()(const wsrep_conn_id_t& key) const { return key; }
        };
        typedef gu::UnorderedMap<wsrep_conn_id_t, Conn, ConnHash> ConnMap;

    public:
        TrxHandle* get_trx(int version,
                           const wsrep_uuid_t& source_id,
                           wsrep_trx_id_t trx_id, bool create = false);
        void unref_trx(TrxHandle* trx);
        TrxHandle* get_conn_query(int version,
                                  const wsrep_uuid_t&,
                                  wsrep_conn_id_t conn_id,
                                  bool create = false);
        // Discard trx handle
        void discard_trx(wsrep_trx_id_t trx_id);
        void discard_conn(wsrep_conn_id_t conn_id);
        void discard_conn_query(wsrep_conn_id_t conn_id);
        std::ostream& operator<<(std::ostream& os) const;
        Wsdb();
        ~Wsdb();

    private:
        // Create new trx handle
        TrxHandle* create_trx(int, const wsrep_uuid_t&, wsrep_trx_id_t trx_id);
        Conn& create_conn(wsrep_conn_id_t conn_id);

        static const size_t trx_mem_limit_ = 1 << 20;
        TrxMap       trx_map_;
        ConnMap      conn_map_;
        gu::Mutex    mutex_;
    };

}


#endif // GALERA_WSDB_HPP
