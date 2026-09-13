---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: composable-mutator-framework
  surfaces:
    - "lib/src/mutagens/mutagen.dart"
    - "lib/src/engine/mutation_visitor.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0008"
---
# 0008: Composable mutagen framework

- Status: accepted

## Context

- Mutagens are the most-edited part of a mutation tool; they must be quick to
  write and easy to read.
- Architecture rails: small classes, one file per class, patterns where they
  clarify (see `AGENTS.md`).

## Decision

- A mutagen declares: node kind, guard predicate, replacement(s).
- Simple operator swaps are pure data (`'+' → ['-']`) on a shared base class.
- Base classes guard by type by default (binary swaps: numeric operands
  only); widening a guard is an explicit override. Easy to write must not
  mean easy to write wrong.
- One AST walk dispatches nodes to registered mutagens (visitor + strategy +
  registry); mutagens never traverse or execute anything.
- Mutagens emit `Mutation` value objects (span, replacement, operator id,
  description); rewriting and execution live in the engine.
- Every stage ships seams the next stage fills, with trivial defaults:
  `CoverageProvider`, `TestSelector`, `ReportSink`.
- API validated by [../plans/spike-mutator-framework.md](../plans/spike-mutator-framework.md).

## Consequences

- The schemata switch ([0010](0010-mutant-schemata.md)) touches zero mutagens.
- Operator profiles (e.g. a coarse function-body set) are registry
  selections, not features.

## Rejected

- Mutagens that own traversal or execution.
- Unbounded operator swarms as the only mode.
- Unguarded pure-data swaps: the spike's guardless `+ → -` broke string
  concatenation.
