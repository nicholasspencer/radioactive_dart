---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: mutant-schemata
  surfaces:
    - "docs/roadmap/v1.0.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0010"
---
# 0010: Mutant schemata

- Status: accepted, planned v1.0

## Context

- Per-mutant recompilation dominates mutation testing cost in most compiled
  languages. Validated by Stryker JS 4.0 ("mutation switching", 20-70%
  faster) and Stryker.NET.
- It does not dominate here: the containment keeps `dart test`'s incremental
  kernel cache, so a suite run after a real `lib/` edit costs what a warm one
  costs (2.36 s vs 2.34 s, measured in
  [../plans/self-run-performance.md](../plans/self-run-performance.md)).
- What schemata buys in Dart is a different thing: with every mutant in one
  build, selecting one is a value rather than a file write, which is what lets
  one process serve more than one mutant
  ([0021](0021-beamline-execution.md)).

## Decision

- Inject all mutants at once as branches selected by a single value; build
  once, expose many times.
- That value is read at runtime, once per isolate, not fixed by a `-D`
  define: a beamline switches mutants without rebuilding
  ([0021](0021-beamline-execution.md)).
- Analyzer-backed rewriting keeps schemata compilable in const contexts.
- A const context cannot read a runtime value, so a mutant inside one is
  built per exposure, like a load-time mutant.
- Static-mutant fallback: load-time code (top-level and const initializers)
  runs per mutant on the subprocess strategy.
- Every injected mutant has to compile, so static viability filtering
  ([0019](0019-static-viability-filtering.md)) is a prerequisite, not an
  optimization.

## Consequences

- Implemented as an engine rewriting strategy; mutagens and reports untouched
  ([0008](0008-composable-mutator-framework.md)).
- Every mutation site costs a branch and a read in the hot path of the code
  under test. The calibration run measures that overhead, since it runs on
  the schemata build, and every exposure is charged with it.
- Alone, this ADR buys nothing measurable in Dart. It ships with
  [0021](0021-beamline-execution.md) or not at all.
