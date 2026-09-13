---
status: accepted
date: 2026-08-21
decision-makers: []
register:
  spec: 1
  slug: beamline-execution
  surfaces:
    - "docs/roadmap/v1.0.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0021"
---
# 0021: Beamline execution

- Status: accepted, planned v1.0

## Context

- The floor of the current design is the process boundary: `dart test` costs
  ~2.3 s before any mutated code runs, and a routed self-run's killed mutants
  had a 9.9 s median where the mutated code itself runs for milliseconds
  ([../plans/self-run-performance.md](../plans/self-run-performance.md)).
- Recompilation is not the cost ([0010](0010-mutant-schemata.md)); loading a
  suite from scratch, once per mutant, is.
- The floor a run can reach is the sum, over mutants, of the cheapest test
  that kills each one. Everything above that is apparatus.

## Decision

- A beamline is a worker process that loads the schemata build once
  ([0010](0010-mutant-schemata.md)) and runs exposure after exposure against
  it.
- An exposure is one mutant against one test. It replaces the mutant as the
  unit of work ([0011](0011-per-test-coverage-routing.md),
  [0017](0017-parallel-classification.md)).
- Selecting a mutant is assigning a value, not writing a file, so a
  containment is read-only once its beamline is built
  ([0004](0004-shadow-copy-isolation.md)).
- Each exposure runs in a fresh isolate: state is isolated per exposure
  without paying for a process.
- A beamline is rebuilt whenever it cannot be trusted: after a hang, after a
  load-time mutant ([0010](0010-mutant-schemata.md)), and after a fixed
  number of exposures.
- `package:test`'s runner API is the contract; its reporter events stay the
  evidence behind every verdict ([0006](0006-outcome-taxonomy.md)).
- Subprocess execution stays a peer strategy for what cannot be hosted:
  `flutter test`, custom runners, and suites that need a fresh process per
  file.
- The calibration run records a source report per test, which is what
  per-test routing needs ([0011](0011-per-test-coverage-routing.md)).

## Consequences

- Determinism narrows: outcomes, mutant IDs, and report order stay
  reproducible; the test that killed a mutant and every measured duration do
  not ([0007](0007-deterministic-execution.md)).
- Test pollution changes class. A leaky test can corrupt later exposures in
  its beamline instead of only its own run; the rebuild policy bounds it, and
  a suite that only passes unhosted falls back to the subprocess strategy.
- A fresh isolate does not reset process state: working directory,
  environment, ports, and temp directories are shared by every exposure in a
  beamline.
- Half-lives become per exposure and measured
  ([0006](0006-outcome-taxonomy.md)).
- Workers follow the core count, since a beamline runs one exposure at a time
  ([0017](0017-parallel-classification.md)).
- A hosted suite still spawns processes of its own; the kill discipline in
  [0006](0006-outcome-taxonomy.md) applies to a beamline as it does to a
  suite.

## Rejected

- Optimizing around one `dart test` per mutant: the process boundary is the
  floor, and it is 2.3 s.
- Reusing one isolate across exposures: leaked state changes verdicts
  silently, and silently is the one way a mutation tester must not be wrong.
- Writing our own test runner: every verdict and every timing already depends
  on the reporter contract.
