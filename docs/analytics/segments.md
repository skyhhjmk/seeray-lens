# Audience segments

Segments are named, reusable rules for grouping sessions. Open a site's **Segments** tab to create, edit, enable, disable, preview, or remove a segment. The rule editor presents fields and operators directly; rule JSON is an internal API/storage representation, not part of the user workflow.

## Available conditions

| Field | Meaning | Conditions |
| --- | --- | --- |
| Visitor type | New or returning visitor for the session | Equals, does not equal |
| Entry page | Session landing path | Text comparisons, is set, is not set |
| Campaign source / medium / name | Initial UTM attribution for the session | Text comparisons, is set, is not set |
| Bounced visit | Whether the session was a bounce | Yes, no |
| Page views | Number of page views in the session | Equals, greater/less than, at least, at most |
| Event type / event page | An event recorded during the session | Text comparisons, is set, is not set |
| Custom property | A configured event property value | Text comparisons, is set, is not set |

Rules can be combined with **all rules** (AND) or **any rule** (OR). A segment accepts 1–10 rules and up to 30 saved definitions per site. Custom-property rules use enabled custom dimensions, so the property picker uses the dimension's human-readable name.

## Preview and permissions

Preview uses the selected reporting date range and reports matching sessions, distinct visitors, page views, bounce rate, and the top pages within matched sessions. Matching is session-based: event conditions match when the session contains an event satisfying the condition. Workspace members can view definitions and previews; workspace owners and admins can change them.

The site-wide report selector applies the chosen segment to the dashboard, visitor, acquisition, behaviour, goal, and custom-dimension reports. With a segment selected, reports evaluate session facts and their associated in-range events instead of reusing whole-site aggregates. The filter is not currently applied to heatmap or recording views, nor to configuration lists such as goal definitions.
