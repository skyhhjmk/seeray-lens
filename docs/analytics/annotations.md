# Analytics annotations

Annotations attach concise operational context to a site-local calendar date. Use them for launches, campaign changes, incidents, migrations, or other events that may explain a traffic or conversion change.

Workspace members with access to a site can read its annotations. Owners and administrators can add, edit, and delete them. Notes are limited to 500 characters, filtered by the selected analytics date range, and shown as markers on dashboard trend charts; selecting a date chip reveals all notes for that date. They are not visitor-level data and do not affect aggregation or segmentation.

The date is stored as a `DATE` and interpreted in the site's timezone. Annotations are deleted with their site. The analytics Annotations tab provides a grouped timeline and date-range controls, while dashboard trend markers keep the notes close to the report they explain.

The authenticated API is `GET/POST /api/v1/sites/{siteId}/annotations` and `PUT/DELETE /api/v1/sites/{siteId}/annotations/{annotationId}`. List ranges are limited to 366 days. Mutation endpoints follow the site's workspace owner/admin boundary and are included in the site audit log.
