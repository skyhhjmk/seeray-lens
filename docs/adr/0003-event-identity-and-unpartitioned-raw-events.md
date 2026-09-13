# ADR 0003: Distinct event identities and unpartitioned raw events

**Status:** Accepted

Use `client_event_id` for client/message idempotency and UUIDv7 `ingest_id` for service identity. In 1.0 use an unpartitioned raw table with `UNIQUE(site_id, client_event_id)`.

PostgreSQL unique constraints on a partitioned table must include partition keys. A future `PARTITION BY received_at` migration therefore cannot retain the current global uniqueness guarantee unchanged. Partitioning requires a deliberate deduplication redesign, such as a separate unpartitioned idempotency registry with retention aligned to retry/replay requirements, before migration. It is not a no-cost schema change.
