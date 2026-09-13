# ADR 0004: Exact unique visitors and additive aggregates

**Status:** Accepted

Store additive counters and sums, deriving rates and averages from their bases. Use exact deduplicated visitor facts per required reporting grain for Hour/Day/Week/Month UV. Do not add UV across lower-grain aggregates and do not introduce approximate sketches in 1.0.
