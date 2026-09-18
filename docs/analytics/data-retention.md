# Analytics data retention

Each site has independent raw-event and aggregate retention periods. The scheduled retention worker runs daily and deletes old raw events based on `received_at`, then removes daily aggregate rows and session facts older than the configured aggregate window. Expired sessions are removed from visitor profiles as well; visitor first/last seen and visit totals are recalculated from the sessions that remain.

Facts and aggregate rows inside the configured aggregate period are not rebuilt from raw events during cleanup. Routine report refreshes reconcile only the requested time window and preserve older materialized facts, so purging raw events does not erase retained historical session or aggregate reports.

Event-level reports, segmentation, and custom dimensions that query `raw_event` cannot reconstruct details after the raw window expires. Their historical results can therefore be incomplete even while standard daily/session aggregates remain available. Set the aggregate period at least as long as the raw period; the site settings validation enforces this.

Cleanup is batched for large installations and writes a site-level summary to the application log. A failed run is retried by the next daily execution.
