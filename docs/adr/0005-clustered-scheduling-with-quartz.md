# ADR 0005: Quartz clustered scheduling with PostgreSQL JDBC store

**Status:** Accepted

Scheduled analytics email delivery uses Quarkus Quartz clustered mode backed by PostgreSQL. It is selected over ad-hoc advisory locks because it gives persistent schedules and operational job state while providing a single cluster-coordination mechanism. Future aggregation, retention, rebuild, and maintenance jobs should use the same store. Quartz tables are installed through Liquibase; ad-hoc destructive upstream schema setup is not used.
