# Experiment targeting

Experiments are managed from the site's A/B tests panel. The visual editor defines the name, control and variant labels, and optional audience targeting. The first variant is the control used by the report. Audience rules are shown as form controls; saved-segment rules are not copied into tracker configuration or exposed to the visitor browser.

Page path prefixes match the exact path or descendants at a path boundary: `/pricing` matches `/pricing` and `/pricing/checkout`, but not `/pricing-old`. Multiple paths are ORed. Selected device types are also ORed; if both page and device filters are configured, both groups must match. Leaving both groups empty includes all visitors. Supported client device types are desktop, mobile, tablet, and other.

The origin-checked tracker request includes the installer's site-scoped anonymous visitor ID. The server returns an experiment with saved-segment targeting only when that visitor has at least one recorded session matching the enabled segment in the selected 7-, 30-, or 90-day lookback. New visitors and visitors without a recorded matching session are excluded until a matching session is available. The server returns only eligible experiment names, variants, and page/device targeting; it does not return segment IDs, names, or rules to the browser. The visitor ID is used only for this eligibility check and is not persisted by the experiment endpoint.

`SeeRay.assignExperiment(name)` checks the returned page/device targeting before reading or writing the visitor's stable assignment and before sending an `experiment_exposure` event. Call it after `SeeRay.ready()` so both experiment definitions and server-side segment eligibility have loaded. A non-targeted call returns no variant and creates no exposure. Segment membership is based on recorded analytics sessions, not a live evaluation of an unsubmitted current page.

Segments in use by an experiment cannot be disabled or deleted; remove them from the experiment first. Real-browser deployment acceptance remains open.

## Lifecycle and traffic layers

Create experiments as drafts. From each experiment card, use **Manage lifecycle** to start a draft, pause or complete a running experiment, resume or complete a paused experiment, or archive an experiment. Completed experiments stop receiving new exposures while keeping their report available. Archived experiments are read-only; deletion is offered only after archiving and removes the definition/report entry.

An experiment's name, variants, audience targeting, and traffic-layer membership become immutable after its first recorded `experiment_exposure`. The editor shows this lock and hides editing controls; the server independently rejects configuration changes. Lifecycle transitions remain available so an exposed experiment can still be paused, completed, or archived. Create a new experiment to test a changed setup.

Experiments are independent by default. Turn on **Share a traffic layer** to choose an existing site layer or create a reusable layer ID (letters/digits with optional `_` or `-`, up to 64 characters). Among the server-eligible running experiments in a layer, the definitions endpoint returns one stable candidate per visitor and layer. The tracker stores that experiment-level layer assignment in site-scoped local storage and applies page/device targeting before recording exposure. Independent experiments do not compete with experiments in a layer. If the chosen candidate does not match its page/device rules, that visitor is not exposed to another experiment in the same layer on that request.

Layer selection is stable while the chosen experiment remains in the returned candidate set. If layer membership or server-side segment eligibility changes, the tracker may choose another currently eligible candidate. Keep experiments in one layer for experiences that must never be shown together, and use lifecycle controls to stop experiments before replacing layer membership. Visitor assignment is site-scoped; no visitor identifier is stored by the definitions endpoint.

## Sample planning and report uncertainty

The visual experiment editor includes a sample-size estimate. Set the expected control conversion rate and the smallest relative lift worth detecting; choose a confidence level (90%, 95%, or 99%) and statistical power (80% or 90%). The estimate assumes equal allocation, independent two-arm comparisons, and a two-sided normal approximation. It shows the estimated exposure count per variant and the traffic total for the configured number of variants. For three or more variants, the total does not include a multiple-comparison correction. Treat this as a planning aid, not a stopping rule; actual traffic and conversion behavior may differ from the assumptions.

Experiment reports show each variant's observed conversion rate with a pointwise 95% Wilson score interval. For non-control variants, the report also shows the absolute conversion-rate difference from control with a pointwise 95% Newcombe-Wilson interval, relative lift, and the existing two-sided significance estimate. Intervals and p-values are not adjusted for multiple comparisons, so the false-positive risk rises when comparing many variants. The interval describes uncertainty in the observed data; a non-significant result is not proof that variants are equivalent.
