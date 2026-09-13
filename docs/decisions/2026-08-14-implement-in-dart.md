---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: implement-in-dart
  surfaces:
    - "pubspec.yaml"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0001"
---
# 0001: Implement in Dart

- Status: accepted

## Context

- Rust-based tools cannot use Dart's official parser.
- Binary distribution (Scoop/Homebrew/zips) hurts discoverability and setup.
- The bottleneck is compiling/running tests, not parsing.

## Decision

- Write the tool in Dart.

## Consequences

- Direct access to `package:analyzer` ([0002](0002-parse-with-official-analyzer.md)).
- Ships via pub.dev ([0003](0003-distribution-and-sdk-resolution.md)).
- No performance loss: speed comes from architecture ([0010](0010-mutant-schemata.md), [0011](0011-per-test-coverage-routing.md)).

## Rejected

- Rust or another systems language: forfeits the official parser; raw speed
  buys nothing here.
