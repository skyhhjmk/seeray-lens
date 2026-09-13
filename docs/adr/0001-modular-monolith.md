# ADR 0001: Modular monolith

**Status:** Accepted

Use one Quarkus deployable with explicit domain boundaries. Scale collector and worker roles independently from the same image when needed. This preserves transactional and operational simplicity without precluding later extraction based on demonstrated constraints.
