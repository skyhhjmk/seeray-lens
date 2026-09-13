# ADR 0002: Privacy-first anonymous identity and URL minimization

**Status:** Accepted

Use random, Tracking-ID-scoped visitor UUIDs in localStorage and random session UUIDs in sessionStorage. Do not use cookies, fingerprinting, full IP persistence, or cross-site identity. Respect DNT by stopping all sends. Persist normalized URL origin/path only; discard fragments and arbitrary query parameters while separately extracting UTM fields.
