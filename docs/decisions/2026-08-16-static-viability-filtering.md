---
status: accepted
date: 2026-08-16
decision-makers: []
register:
  spec: 1
  slug: static-viability-filtering
  surfaces:
    - "lib/src/engine/viability_checker.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0019"
---
# 0019: Static viability filtering

- Status: accepted

## Context

- Flipping `==`/`!=` or `&&`/`||` around a null check can break flow-based
  type promotion in code the mutation never touched; such mutants do not
  compile.
- Dogfooding v0.1: 26 of 174 mutants were unviable and burned ~34 minutes of
  test time (avg 79 s each) before failing to load.
- Syntactic gates cannot decide viability: whether a flip compiles depends
  on promotion uses elsewhere in the function. A "never mutate null checks"
  gate would also have dropped 6 viable mutants, one a genuine survivor.

## Decision

- Mutants must compile; the engine verifies this statically instead of
  trusting mutagen guards.
- After generation, each covered mutant's file is re-resolved through an
  in-memory analyzer overlay; error diagnostics classify the mutant
  `unviable` with no test run.
- Only `COMPILE_TIME_ERROR` and `SYNTACTIC_ERROR` diagnostics deny
  viability; warnings and lints escalated to error severity do not.
- Only the mutated file is re-analyzed: mutagens rewrite expressions inside
  bodies, which cannot change a file's API. Declaration-changing mutagens
  must widen the check first.

## Consequences

- Division of labor: mutagen guards minimize unviable mutants by reading
  promotion facts off the resolved AST (`PromotionDependence`); this filter
  eliminates the remainder. Guards err toward keeping a mutant.
- The check reuses generation's analysis state and processes a file's
  mutants as one batch, so a file is resolved once per mutant instead of
  twice. Both stages scope that state, so the resolved units are collectible
  before the first worker runs ([0016](0016-wide-event-logging.md)).
- Schemata ([0010](0010-mutant-schemata.md)) requires every injected mutant
  to compile; this filter is its prerequisite.
- The TCE pass ([0012](0012-tce-equivalent-detection.md)) becomes a peer
  filter stage on the same infrastructure.

## Rejected

- Blanket null-comparison gates in mutagens: drop viable mutants and stay
  unsound (`is` checks, definite assignment).
- Reimplementing flow analysis at generation time: fragile duplication of
  the compiler.
