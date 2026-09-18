# Product parity ledger

This ledger is the completion contract for the Matomo-compatible product. A source file or API alone is not completion: every row needs automated checks and the stated runtime acceptance.

| Domain | Current implementation | Still required for parity |
| --- | --- | --- |
| Collection | Page views, events, goals, DNT, consent gating, downloads/outlinks, data layer, explicit site-search tracking and opt-in search-form capture, labelled content impressions and interactions, opt-in Core Web Vitals (LCP, INP, CLS) | Mobile SDKs |
| Privacy | Site-scoped IDs, URL minimisation, opt-out API and embeddable banner | Admin consent policy, hosted opt-out page, browser acceptance |
| Reporting | Overview, pages/titles, traffic, events, configured goals, segmented core reports, technology, visitor-location breakdowns, live visits, personal saved dashboards, a bounded visual custom-report builder with up to four session/event/custom-dimension breakdowns and named formulas over allowlisted measures, per-widget CSV/JSON/PDF exports, scheduled weekly/monthly email reports with CSV attachments, and configurable daily comparative alerts with email/Slack/Teams delivery | Nested arbitrary event-property paths and browser acceptance |
| Behaviour | Heatmaps, recordings, page titles, entry/exit pages, tracked events, segment-aware five-step page-flow explorer, site-search terms/results, content impression/interaction reports, and segment-aware page-level Web Vitals reports | Page overlay and richer transition drill-downs |
| Attribution | Session-level UTM source/medium/campaign/term/content aggregates, deterministic direct/referral/search/social/AI-assistant classification, and segment-aware first-touch/last-touch/linear/position-based/time-decay goal attribution with graphical goal/window/model controls | Ad click IDs, ad cost import and external ad-platform export |
| Conversion | Goal rules and value, conversion session count/rate, comparisons against the previous equal-length period or between two saved audiences, ordered funnel definitions/reports, and multi-touch conversion attribution | Browser acceptance |
| Tag manager | Site-scoped containers, graphical event/custom-code tags and event-property filters, workspace-shared visual tag-template library, immutable versions, independent development/staging/production releases and rollback, origin-checked delivery, runtime variables, a no-code draft dry-run, short-lived live-site preview/debug sessions with analytics suppression and bounded query-stripped logs, and consent-aware execution | Approval workflows, fine-grained script governance, and real-browser acceptance on an allowed domain |
| Experimentation | Site-scoped definitions with draft/running/paused/completed/archived lifecycle, archive-before-delete and post-exposure setup locking; stable client assignment; visitor-stable mutual-exclusion traffic layers; URL path-prefix, device, and server-evaluated saved-segment targeting with explicit lookback; exposure events; unique-session conversion reports; control-relative lift/p-value/significance; 95% Wilson/Newcombe-Wilson confidence intervals; visual admin editor and adjustable sample-size planner | Real-browser acceptance for assignment persistence, page/device targeting, layer exclusivity, and report continuity |
| Visitor intelligence | Anonymous visitor/session facts and log UI, saved segments, technology and trusted-proxy location dimensions, weekly first-visit cohorts with retention matrix and first-session segment filtering | Full visitor profiles and richer cohort definitions |
| Operations | Site-scoped audit log of successful settings and analytics-configuration mutations | Workspace membership/login/token history, read-access history and configurable retention |

## Evidence gates

1. Unit/integration tests cover ingestion, access control, aggregation and query semantics.
2. Browser acceptance covers tracker snippets, consent/opt-out, navigation, first-party and cross-origin deployment.
3. Production acceptance verifies queue failure, aggregation retry, retention, observability and role boundaries.
