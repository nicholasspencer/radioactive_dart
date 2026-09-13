---
status: accepted
date: 2026-08-15
decision-makers: []
register:
  spec: 1
  slug: parallel-classification
  surfaces:
    - "lib/src/engine/engine.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0017"
---
# 0017: Parallel classification

- Status: accepted

## Context

- Serial whole-suite-per-mutant runs take hours on real projects; the
  self-run took over an hour for 84 mutants.
- Mutant classifications are independent: each needs only its own mutated
  copy of the project.

## Decision

- A worker pool classifies mutants concurrently; pulled forward from v0.1.
- Each worker owns one containment copy ([0004](0004-shadow-copy-isolation.md));
  mutants never share a mutated tree.
- Only the baseline containment is built and `dart pub get`-ed, so dependency
  resolution runs once per run. One pristine clone of it is taken before the
  background reading; the workers are cloned from that template after
  generation, capped by the mutant count. No worker inherits what the reading's
  suite writes into the package tree, and a red reading
  ([0005](0005-mandatory-baseline-verification.md)) aborts having copied the
  tree twice instead of once per job.
- Workers pull from one shared queue; the unit of work stays generic for
  the v1.0 switch to "mutant × covering test".
- `--jobs`/`-j` sets the worker count; default `max(1, cores ~/ 2)` because
  every suite process parallelizes internally already.
- Determinism ([0007](0007-deterministic-execution.md)) is preserved:
  results are stored by mutant index, so completion order never changes the
  report. Progress output follows completion order.
- Under [0021](0021-beamline-execution.md) a worker owns one beamline and
  runs one exposure at a time, so jobs default to the core count and no suite
  concurrency is divided. The `cores ~/ 2` default and the split below belong
  to the subprocess strategy, where each suite parallelizes internally.
- Suite concurrency is divided among the requested jobs
  (`dart test --concurrency = cores ~/ jobs`): the total stays near the
  core count instead of oversubscribing multiplicatively.
- The background reading runs once with that same per-suite concurrency, so
  half-lives ([0006](0006-outcome-taxonomy.md)) are calibrated under the
  same conditions the mutant runs see. The first parallel self-run skipped
  this and drowned in load-induced timeouts (53 of 79).

## Rejected

- Sharing one containment with a lock: serializes everything again.
- Defaulting to all cores: nested test-runner parallelism already uses
  them; oversubscription inflates timings against a serial baseline.
- Isolates instead of async workers: the work is process-spawning I/O, not
  Dart-side CPU.
