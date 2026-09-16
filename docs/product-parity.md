# Product parity ledger

This ledger is the completion contract for the Matomo-compatible product. A source file or API alone is not completion: every row needs automated checks and the stated runtime acceptance.

| Domain | Current implementation | Still required for parity |
| --- | --- | --- |
| Collection | Page views, events, goals, DNT, consent gating, downloads/outlinks, data layer | Web vitals, site search, content tracking, mobile SDKs |
| Privacy | Site-scoped IDs, URL minimisation, opt-out API and embeddable banner | Admin consent policy, hosted opt-out page, browser acceptance |
| Reporting | Overview, pages, traffic, events, configured goals and visitor log | Segments, real-time, custom dashboards, exports, scheduled reports, alerts |
| Behaviour | Heatmaps and recordings | Entry/exit, transitions, user flow, page overlay, performance reports |
| Attribution | UTM/source/medium/campaign aggregates | Search/social/ad click IDs, attribution models and ad cost import |
| Conversion | Goal rules, value, conversion session count/rate, ordered funnel definitions/reports and admin panel | Comparison and attribution reports |
| Tag manager | Site-scoped containers, JSON drafts, versioning, publish/rollback, origin-checked delivery, admin panel, and consent-aware event/page-view execution | Rich typed tags/triggers/variables, preview, arbitrary script governance and browser acceptance |
| Experimentation | Site-scoped definitions, stable client assignment, exposure events, unique-session conversion reports, control-relative lift/p-value/significance, and admin panel | Targeting/segmentation and browser acceptance |
| Visitor intelligence | Anonymous visitor/session facts and log API | Visitor profile UI, cohorts, segments and retention reports |

## Evidence gates

1. Unit/integration tests cover ingestion, access control, aggregation and query semantics.
2. Browser acceptance covers tracker snippets, consent/opt-out, navigation, first-party and cross-origin deployment.
3. Production acceptance verifies queue failure, aggregation retry, retention, observability and role boundaries.
