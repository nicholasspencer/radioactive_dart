---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: deterministic-execution
  surfaces:
    - "lib/src/engine/mutant_generator.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0007"
---
# 0007: Deterministic execution

- Status: accepted

## Context

- Identical runs with different scores make the tool unusable as a CI gate.
- Sharding and history files need stable identifiers.

## Decision

- Stable mutant IDs: file + node offset + operator + replacement; the
  replacement disambiguates multi-swap operators (`'+' → ['-', '*']`).
- Mutations sorted by (file, offset, operator, replacement) before ID
  assignment: AST visit order (parent before child) is not source order.
- Seeded ordering; isolated test processes.
- Identical input always produces an identical report.
- Determinism covers verdicts, mutant IDs, and report order. It does not
  cover the test that killed a mutant or any measured duration: both are
  recorded as evidence ([0021](0021-beamline-execution.md)) and both may
  differ between runs of the same input.

## Rejected

- Nondeterministic parallel classification.
- Randomized sampling as a roadmap feature: fights score comparability;
  trivial to add later as a flag if ever needed.
