---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: tce-equivalent-detection
  surfaces:
    - "docs/roadmap/v2.0.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0012"
---
# 0012: TCE equivalent-mutant detection

- Status: accepted, planned v2.0

## Context

- Equivalent mutants inflate survivor counts and waste review time.
- Trivial Compiler Equivalence: compile mutant and original, compare output.

## Decision

- Compile candidate survivors to kernel; hash-compare against the original;
  mark matches `Equivalent`.
- Implemented as a filter stage between execution and reporting.

## Consequences

- The `Equivalent` enum value exists since the MVP
  ([0006](0006-outcome-taxonomy.md)); reports need no schema change.
