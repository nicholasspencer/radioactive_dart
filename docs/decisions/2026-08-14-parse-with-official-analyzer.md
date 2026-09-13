---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: parse-with-official-analyzer
  surfaces:
    - "lib/src/engine/project_analysis.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0002"
---
# 0002: Parse with the official analyzer

- Status: accepted

## Context

- Community grammars trail the language and degrade silently: unparseable code
  is skipped while the score still looks healthy.
- Type information prevents invalid and equivalent mutants.

## Decision

- Generate mutants from `package:analyzer`'s resolved AST.
- Precedent: Stryker.NET mutates via Roslyn, the official compiler API.

## Consequences

- New syntax is supported the day it lands in stable.
- Mutants are always compilable and type-aware.
- `AnalysisContextCollection` requires absolute normalized paths; normalize
  with `package:path` at the boundary.

## Rejected

- Third-party grammars (e.g. tree-sitter): silent syntax lag.
- Raw-text/regex mutation as primary engine: shallow mutant sets on modern
  constructs, invalid/equivalent mutants. Acceptable only as an explicit,
  clearly-labeled fallback for files the analyzer refuses to parse.
