---
status: accepted
date: 2026-08-14
decision-makers: []
register:
  spec: 1
  slug: stryker-json-primary-report
  surfaces:
    - "lib/src/report/stryker_json_sink.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "0009"
---
# 0009: Stryker JSON as primary report

- Status: accepted

## Context

- A custom format would need its own tooling forever.
- The Stryker `mutation-testing-report-schema` has a free report viewer,
  dashboard, and ecosystem.

## Decision

- Emit Stryker JSON from the MVP on.
- Later formats (HTML, LLM Markdown) are additive `ReportSink`
  implementations.

## Consequences

- Browsable HTML via the Stryker viewer without writing any HTML.
- Machine-readable output from day one.

## Rejected

- A throwaway custom JSON schema for the MVP.
- JUnit XML output (dropped from the roadmap).
