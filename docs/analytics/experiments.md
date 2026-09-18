# Experiment targeting

Experiments are managed from the site's A/B tests panel. The visual editor defines the name, control and variant labels, and optional audience targeting. The first variant is the control used by the report.

Page path prefixes match the exact path or descendants at a path boundary: `/pricing` matches `/pricing` and `/pricing/checkout`, but not `/pricing-old`. Multiple paths are ORed. Selected device types are also ORed; if both page and device filters are configured, both groups must match. Leaving both groups empty includes all visitors. Supported client device types are desktop, mobile, tablet, and other.

The published tracker definition carries the targeting rules. `SeeRay.assignExperiment(name)` checks eligibility before reading or writing the visitor's stable assignment and before sending an `experiment_exposure` event. Call it after `SeeRay.ready()` so the site definitions have loaded. A non-targeted call returns no variant and creates no exposure. No form values, URL query strings, or visitor profile data are needed for these checks.

This is URL/device targeting, not saved-segment targeting. Saved segment evaluation on experiments and real-browser deployment acceptance remain open parity items.
