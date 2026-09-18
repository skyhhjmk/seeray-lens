# Experiment targeting

Experiments are managed from the site's A/B tests panel. The visual editor defines the name, control and variant labels, and optional audience targeting. The first variant is the control used by the report. Audience rules are shown as form controls; saved-segment rules are not copied into tracker configuration or exposed to the visitor browser.

Page path prefixes match the exact path or descendants at a path boundary: `/pricing` matches `/pricing` and `/pricing/checkout`, but not `/pricing-old`. Multiple paths are ORed. Selected device types are also ORed; if both page and device filters are configured, both groups must match. Leaving both groups empty includes all visitors. Supported client device types are desktop, mobile, tablet, and other.

The origin-checked tracker request includes the installer's site-scoped anonymous visitor ID. The server returns an experiment with saved-segment targeting only when that visitor has at least one recorded session matching the enabled segment in the selected 7-, 30-, or 90-day lookback. New visitors and visitors without a recorded matching session are excluded until a matching session is available. The server returns only eligible experiment names, variants, and page/device targeting; it does not return segment IDs, names, or rules to the browser. The visitor ID is used only for this eligibility check and is not persisted by the experiment endpoint.

`SeeRay.assignExperiment(name)` checks the returned page/device targeting before reading or writing the visitor's stable assignment and before sending an `experiment_exposure` event. Call it after `SeeRay.ready()` so both experiment definitions and server-side segment eligibility have loaded. A non-targeted call returns no variant and creates no exposure. Segment membership is based on recorded analytics sessions, not a live evaluation of an unsubmitted current page.

Segments in use by an experiment cannot be disabled or deleted; remove them from the experiment first. Real-browser deployment acceptance remains open.
