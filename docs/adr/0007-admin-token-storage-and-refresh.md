# ADR 0007: Admin token storage and refresh

**Status:** Accepted

The Flutter Web admin keeps the access token and opaque refresh token in memory only for 1.0. Reloading the page requires a new login. This deliberately avoids putting a bearer refresh credential in `localStorage`, which would increase exposure to an XSS compromise.

The REST client attaches the access token as an `Authorization: Bearer` header. A single `401` for an otherwise normal authenticated request starts a single-flight refresh: concurrent requests share that refresh, successful refresh retries each original request once, and refresh failure clears the in-memory state and routes to login. `403` and `404` are authorization/resource outcomes and never trigger a refresh.

The refresh token is opaque, is sent only to the refresh/logout endpoints, and is never logged or persisted by the admin. A later persistent-session design must use an explicit threat-modelled solution, such as an HttpOnly same-site cookie with CSRF protection or a platform secure-storage mechanism. It must not silently add refresh-token localStorage.
