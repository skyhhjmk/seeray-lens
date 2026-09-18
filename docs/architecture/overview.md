# SeeRay Lens 1.0 Architecture

## Scope and boundaries

SeeRay Lens is a modular monolith: one Quarkus codebase with explicit `auth`, `user`, `site`, `tracking`, `visitor`, `session`, `event`, `analytics`, `aggregation`, `retention`, and `infrastructure` domains. HTTP collection remains inexpensive; asynchronous processing owns persistence and aggregation. The Flutter admin consumes only versioned REST contracts. The browser tracker is a standalone TypeScript package with no framework runtime.

```text
Tracker -> Collector -> RabbitMQ exchange -> ingest queue -> Worker -> PostgreSQL raw events -> Live Visitors API
                                                              -> aggregation -> aggregate tables -> Analytics API -> Flutter
                         Redis: tracking rate limit
```

Redis is never the only durable source of analytics facts. Elasticsearch is an optional observability integration, not a startup dependency.

## Privacy and identity

The tracker is cookie-free, not storage-free. When consent is not required—or after required consent is granted—and Do Not Track is off, it creates a random UUID visitor identifier in `localStorage`, keyed with the public Tracking ID. Before that point it keeps only in-memory ephemeral IDs and does not install data-reading listeners or load optional analytics configuration. This identifier is site-isolated; it is never derived from IP, UA, or browser fingerprinting and must not be correlated across sites. A random session UUID is held in `sessionStorage`. Opt-out removes the site's tracker-owned storage keys and preserves a denial choice where storage is available. The server treats the session ID as an input to validate and derive the final business session boundary.

When Do Not Track is enabled, the tracker sends nothing. Full IP addresses are neither persisted nor used to build stable identity. A future strict no-persistent-identifier mode is possible but is not the 1.0 default.

An application may optionally set an opaque User ID after consent. Collection converts it to a site-scoped hash before persistence. Visitor profile history can link sessions for a uniquely identified browser profile; conflicting accounts are kept separate. Aggregate reports, segments, and cohorts remain browser-scoped. See [cross-device visitor profiles](../analytics/visitor-identities.md) for identifier safety and scope.

URLs are normalized before persistence: origin and path are retained, fragments are discarded, and arbitrary query strings are discarded. Explicitly approved UTM fields are extracted independently. This avoids default retention of tokens, emails, user IDs, orders, searches, and session identifiers.

## Event identity and raw facts

The tracker creates `client_event_id` for browser retry and at-least-once message idempotency. The service creates `ingest_id` as its internal event identity, preferring UUIDv7. These are intentionally distinct names throughout Java, database, messages, and API contracts.

`raw_event` remains unpartitioned in 1.0 and enforces `UNIQUE(site_id, client_event_id)`. It stores server receive time, normalized page data, derived metadata, and bounded JSONB event data. Retention removes raw data after the site policy; aggregates have their own, longer policy.

## RabbitMQ acceptance and overload

The producer publishes persistent messages to exchange `seeray.tracking`, routing key `event.v1`; it is not coupled to a consumer queue. The initial topology is `seeray.tracking.ingest.v1`, `seeray.tracking.retry.v1`, and `seeray.tracking.dlq.v1`, all durable quorum queues where appropriate. Publisher confirms are required before collector success. The collector returns `202 Accepted` only after broker confirmation; broker unavailability returns `503` plus retry guidance.

Consumers use manual ACK only after the database batch transaction commits. Retry is application-owned and bounded through the retry queue; the quorum queue delivery limit is configured higher than the application retry budget so it cannot unexpectedly bypass retry routing. Exhausted messages go to the DLQ. Database uniqueness is the final duplicate defence.

No in-memory collector buffer is treated as reliable. Queue depth, oldest message age, disk pressure, confirm latency, consumer lag, batch insert latency, and aggregation delay drive backpressure. Near dangerous backlog levels, collector traffic is throttled or rejected to protect already accepted data.

## Aggregation correctness

Aggregate tables store additive primitives, not pre-averaged values: `page_view_count`, `event_count`, `duration_sum`, `duration_count`, properly bucketed `session_count`, and `bounced_session_count`. Average duration and bounce rate are calculated from those primitives at query time. Upper time grains never average lower-grain averages or rates.

Unique visitors are non-additive. 1.0 prioritizes exact correctness: maintain a deduplicated visitor fact keyed by `(site_id, business_bucket, anonymous_visitor_id)` for each required Hour/Day/Week/Month grain, then count those facts. This costs more storage and write work than sketches but supports exact results, rebuilds, and clear semantics. Probabilistic sketches are explicitly deferred.

Aggregation uses UPSERT and versioned checkpoints, processes an overlap window for late events, and supports an idempotent site/time-range rebuild while raw facts remain retained.

## Scheduling and clustering

Scheduled analytics delivery uses Quarkus Quartz clustered mode with PostgreSQL JDBC store. The same mechanism is reserved for future state-mutating tasks such as aggregation, retention, rebuild, and maintenance; it provides persisted schedules and cluster-wide coordination using the existing durable database. Plain `@Scheduled` is permitted only for non-exclusive local housekeeping.

## Workspace and access

The database owns `organization`, `organization_member`, and `site`; the UI calls an organization a Workspace. Sites always belong to a Workspace, not directly to a user. 1.0 roles are `owner`, `admin`, and `viewer`; no SSO, billing, custom RBAC, enterprise sync, or invitation workflow is included.

## Admin control-plane client

The Flutter Web admin is a Riverpod application which talks only to `/api/v1` REST DTOs. It owns authentication phase, current Workspace, and current Workspace-derived resources. Switching Workspace invalidates/reloads the selected Workspace's Site and API-token views; it does not reuse data from the previous Workspace. Access tokens are sent in the Authorization header, while the opaque refresh token remains in memory for this release. The concrete storage and refresh decision is recorded in ADR 0007.
