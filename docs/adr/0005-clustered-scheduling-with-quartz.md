# ADR 0005: Quartz clustered scheduling with PostgreSQL JDBC store

**Status:** Accepted

Future aggregation, retention, rebuild, and maintenance jobs use Quarkus Quartz clustered mode backed by PostgreSQL. It is selected over ad-hoc advisory locks because it gives persistent schedules and operational job state while providing a single cluster-coordination mechanism. Quartz is added when the first such job is implemented; Phase 1 introduces no state-changing scheduled task.
