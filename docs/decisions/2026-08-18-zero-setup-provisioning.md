---
status: accepted
date: 2026-08-18
decision-makers: []
register:
  spec: 1
  slug: zero-setup-provisioning
  surfaces:
    - "lib/src/engine/coverage_collector.dart"
    - "lib/src/cli/cli.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0020"
---
# 0020: Zero-setup provisioning

- Status: accepted

## Context

- A first run should need no preparation: users install rad and run it.
- Generation and viability analysis read the project directly, so a project
  that was never `pub get`-ed resolves poorly and yields weak mutants.
- Without coverage, every mutant is treated as covered ([0011](0011-per-test-coverage-routing.md)),
  so uncovered code inflates the run and the score is less honest
  ([0013](0013-score-and-honesty-metrics.md)).

## Decision

- Dependencies: rad runs `dart pub get` in the project before analysis.
  This provisions a new project and refreshes a stale package configuration.
- Coverage resolution, in order:

| Order | Condition | Source |
|---|---|---|
| 1 | `--coverage <path>` given | that file |
| 2 | `coverage/lcov.info` exists and records something | that file |
| 3 | otherwise | rad collects it |

- v0.1: collection is its own suite run inside a containment, separate from
  the background reading, so half-lives stay calibrated on an uninstrumented
  run.
- v0.2: the background reading is the calibration run. Green-suite
  verification ([0005](0005-mandatory-baseline-verification.md)), coverage,
  and per-suite timing come from one instrumented pass, which costs a run
  one full suite instead of two. Silence-based half-lives
  ([0006](0006-outcome-taxonomy.md)) are indifferent to the overhead that
  ruled this out before.
- Collection is the default and can be disabled by flag; disabling falls back
  to treating all code as covered.

## Consequences

- A bare `rad` run costs one extra suite run, and reports measured coverage
  instead of assuming full coverage.
- Uncovered mutants report `noCoverage` and never run, so the extra run buys
  back time on projects with uncovered code.
- rad writes `pubspec.lock` and `.dart_tool/` into an unprovisioned project.
- Collected paths are containment-absolute and must map back to
  project-relative paths before routing.
- A collection run that fails or records nothing aborts: assuming full
  coverage inflates the score, assuming none reports every mutant as
  `noCoverage` ([0013](0013-score-and-honesty-metrics.md)).
- A found report that records nothing is stale and is skipped for the same
  reason; a given one is honoured as is.

## Rejected

- Instrumenting the background reading while half-lives were budgets of
  elapsed time: the overhead inflated the base they derived from. Superseded
  by [0006](0006-outcome-taxonomy.md).
- Collecting when the user already supplied or generated a report.
