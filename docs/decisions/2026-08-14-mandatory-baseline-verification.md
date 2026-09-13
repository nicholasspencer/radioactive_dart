---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: mandatory-baseline-verification
  surfaces:
    - "lib/src/engine/engine.dart"
    - "lib/src/engine/run_aborted.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0005"
---
# 0005: Mandatory background reading

- Status: accepted

## Context

- Running against a red suite silently inverts kill semantics and produces a
  confident, wrong report.
- The background reading (baseline run) also provides the timing base for
  half-lives.

## Decision

- A green suite is a precondition for every run; a red background reading
  aborts with a clear message.
- Background timing is recorded for half-life derivation ([0006](0006-outcome-taxonomy.md)).

## Rejected

- Skipping or tolerating a failing background reading.
