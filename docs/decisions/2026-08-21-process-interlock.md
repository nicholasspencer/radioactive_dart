---
status: accepted
date: 2026-08-21
decision-makers: []
register:
  spec: 1
  slug: process-interlock
  surfaces:
    - "lib/src/engine/process_interlock.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0022"
---
# 0022: Process interlock

- Status: accepted

## Context

- A timed-out suite has to die with everything it started. rad's own suite
  starts nested `rad` runs, which start suites of their own, so an escapee is
  not idle: it keeps classifying mutants and spawning children.
- Hunting the tree from a process listing fails in the case that matters. Three
  self-runs leaked 2, then 69, then 127 processes across 24 trees, the last of
  them still spawning two and a half hours after the final timeout
  ([../plans/self-run-performance.md](../plans/self-run-performance.md)).
- Every listing-based kill shares the same defects: the helper that lists
  processes can fail or lag exactly when a loaded machine is hunting a hung
  suite, an empty answer is indistinguishable from "nothing to kill", and a
  process spawned between the listing and the kill is never seen.
- Windows job objects and POSIX process groups are the OS facilities for
  exactly this. Dart exposes neither, but `dart:ffi` reaches the first.

## Decision

- Every suite is admitted to an interlock: a Windows job object created before
  the suite can start anything of its own.
- Membership is inherited, so everything the suite spawns joins it, including
  processes that detach from their parent.
- A timeout calls `TerminateJobObject`: one call, no listing, nothing to race.
- `dart:ffi` binds the four `kernel32` entry points needed
  (`CreateJobObjectW`, `OpenProcess`, `AssignProcessToJobObject`,
  `TerminateJobObject`). No package dependency is added.
- Where no interlock can be created, the run falls back to the process
  snapshot and sweep, which stays the behaviour on every other platform.

## Consequences

- The kill stops depending on anything that can fail under load.
- A process the suite started before it was admitted is outside the job. The
  window is the microseconds between `Process.start` and `admit`, and a test
  runner spends far longer than that starting up.
- Nested runs work: job objects nest since Windows 8, so a `rad` inside a
  suite inside a job creates its own.
- The interlock is not a lifetime guarantee: rad killed outright still leaves
  its suites running, since the job is not set to die with its handle. Adding
  `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` would fix that, and needs an allocator,
  which means a dependency.
- POSIX keeps the sweep, and keeps its known hole: `setsid` is absent from
  minimal images and Dart cannot spawn a process group.

## Rejected

- Retrying and verifying the sweep: cheaper, but still best-effort against a
  runner that spawns constantly, and still silent when the listing fails.
- `taskkill /T`: the same race, plus a process spawn per kill.
