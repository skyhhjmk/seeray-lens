# ADR 0002: Privacy-first anonymous identity and URL minimization

**Status:** Accepted

Use random, Tracking-ID-scoped visitor UUIDs in localStorage and random session UUIDs in sessionStorage. Do not use cookies, fingerprinting as an anonymous identity, full IP persistence, or cross-site identity. A separately enabled site may collect a consent-gated, site-scoped browser fingerprint risk signal only to flag possible same-browser activity; it must never affect UV, session identity, User ID linking, or cross-site correlation. Respect DNT by stopping all sends. Persist normalized URL origin/path only; discard fragments and arbitrary query parameters while separately extracting UTM fields.
