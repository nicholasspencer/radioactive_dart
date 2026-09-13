---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: outcome-taxonomy
  surfaces:
    - "lib/src/model/outcome.dart"
    - "lib/src/engine/outcome_classifier.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0006"
---
# 0006: Outcome taxonomy

- Status: accepted

## Context

- Mature tools (pitest) model every failure mode as a result category.
- A tool exception mid-run loses all completed work.
- A budget of elapsed time cannot separate a hung run from a slow one: it is
  calibrated on an idle background reading and spent under the load the run
  itself creates. Sized that way, a self-run timed out 75 of 709 healthy
  mutants, 31 of them routed to the whole suite
  ([../plans/self-run-performance.md](../plans/self-run-performance.md)).

## Decision

- Every mutant result is data, never an exception:
  `Killed · Survived · NoCoverage · Timeout · Unviable · RunError ·
  MemoryError · Equivalent`.
- The full enum exists from the MVP, even for outcomes produced only by later
  stages.
- The half-life is a budget of silence, not of elapsed time: a run is timed
  out once its reporter has produced nothing for longer than the budget.
  A hung run is silent under any load; a slow one keeps streaming events.
- Budget = `max(longest gap in the background reading × 3, 10 s floor)`.
- A generous total ceiling stays as a backstop against a run that is hung
  but noisy. It no longer has to tell slow from hung, so it does not have
  to be tight.
- Under [0021](0021-beamline-execution.md) the budget is per exposure: the
  calibration run measures every test, so a hung exposure is one that
  outlasts its own measured cost by a factor.
- `Killed`, `Survived`, and `Timeout` remain separate peer outcomes in results.
- Timeouts are inconclusive. They count as neither killed nor survived.
- `--max-timeouts` fails a run when its timeout ceiling is exceeded.
- A timed-out run is killed with everything it spawned, through the interlock
  it was admitted to ([0022](0022-process-interlock.md)). Where none exists,
  the tree is listed while still attached and swept until nothing new appears;
  that fallback is best-effort and has leaked at every scale.

## Rejected

- Uncaught timeouts/OOM/crashes.
- Folding timeouts into killed or survived results.
- Half-life derived from the background reading without a floor: a near-zero
  reading collapses it.
- Half-life as a budget of total elapsed time: idle calibration, contended
  spending, and healthy mutants reported as inconclusive.
