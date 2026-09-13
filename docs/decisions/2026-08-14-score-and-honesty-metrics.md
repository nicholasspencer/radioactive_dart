---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: score-and-honesty-metrics
  surfaces:
    - "lib/src/report/metrics.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0013"
---
# 0013: Score and honesty metrics

- Status: accepted

## Context

- A single score hides whether tests are weak or missing.
- A tool that falls behind the language must say so instead of shipping a
  silently inflated score.

## Decision

- Report MSI and covered-code MSI as separate numbers (Infection).
- MSI = `Killed / (Killed + Survived + NoCoverage)`.
- Covered-code MSI = `Killed / (Killed + Survived)`.
- Timeout rate = `Timeout / (Killed + Survived + Timeout)`.
- Reports show killed, survived, and timed-out counts as peer categories.
- Timeouts do not enter either MSI numerator or denominator.
- Syntax-coverage metric: % of executable AST nodes the operator set can
  mutate, plus a list of node kinds encountered but unhandled.
- v0.2 ships the node-kind census as a warning; v1.0 puts the full metric in
  reports.

## Consequences

- The census is stored in the run result, not just logged.
- `--max-timeouts` prevents a strong MSI from hiding an inconclusive run.
