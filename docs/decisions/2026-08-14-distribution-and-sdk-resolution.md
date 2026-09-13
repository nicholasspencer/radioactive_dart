---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: distribution-and-sdk-resolution
  surfaces:
    - "lib/src/engine/dart_test_runner.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0003"
---
# 0003: Distribution and SDK resolution

- Status: accepted

## Context

- Resolving `dart` from PATH breaks under wrapper scripts (`dart.bat` on
  Flutter/Windows).
- Tools requiring setup lose users before the first run.

## Decision

- Distribute via pub.dev: dev dependency or `dart pub global activate`.
- Spawn test processes via `Platform.resolvedExecutable`.
- Zero-config default: `dart run <tool>` in a project root produces a useful
  report; config and flags only refine it.

## Consequences

- The tool always uses the exact SDK it runs on.
- Discoverable where Dart developers already look.

## Rejected

- PATH-based SDK resolution.
- Binary releases as the primary channel.
