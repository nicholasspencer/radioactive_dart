---
status: accepted
date: 2026-08-15
decision-makers: []
register:
  spec: 1
  slug: run-workspace-lifecycle
  surfaces:
    - "lib/src/run_workspace.dart"
    - "lib/src/rad_paths.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0018"
---
# 0018: Run workspace lifecycle

- Status: accepted, staged v0.1–v0.2

## Context

- Crashed runs leave containments and logs under the resolved rad temp root.
- Old state consumes disk and obscures evidence from the current run.
- Exit cleanup can destroy evidence needed to investigate a failed run.
- Concurrent cleanup must not remove another active run's containment.

## Decision

- Startup cleanup is the first run stage.
- The CLI acquires an exclusive `<rad temp root>/.lock` before cleanup.
- An actively held lock is never stolen.
- A pre-existing lock prompts interactive users before stale-state takeover.
- `--non-interactive` disables prompts and aborts on a pre-existing lock.
- v0.1 aborts on any pre-existing lock. v0.2 adds the prompt and flag.
- After acquiring the lock, startup cleanup removes:
  - the previous tool log;
  - every top-level `containment_*` directory;
  - every immediate child of the run-log directory.
- The run-log directory itself is never removed.
- Failure to clean any target aborts before mutant generation and releases
  the lock: the run never started.
- Every exit removes the lock file, a failed run included: a stranded lock
  blocks every later run. Only a killed process leaves it behind.
- No containment or evidence cleanup runs at exit.

## Consequences

- Every run starts without abandoned containments or logs.
- Evidence remains available until another run starts.
- Concurrent CLI runs cannot corrupt each other's workspace.
- CI uses `--non-interactive` to fail instead of waiting for input.

## Rejected

- Exit cleanup: removes evidence from the run that needs investigation.
- Deleting the run-log directory: consumers may rely on the stable path.
- Ignoring an existing lock: cleanup could destroy an active run.
