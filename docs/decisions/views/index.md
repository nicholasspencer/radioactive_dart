# Architecture decision records

Decisions distilled from the tool survey in [../research/](../research/index.md)
and mature tools in other ecosystems
([../research/other-ecosystems.md](../research/other-ecosystems.md)).

How the decisions compose at runtime:

```mermaid
flowchart TD
    A[lock + startup cleanup] --> P[dependency resolution: pub get]
    P --> B[containment: filtered project or workspace copy]
    B --> C[calibration reading: green suite, coverage, per-test timing]
    C --> E[routing: a given lcov overrides what was measured]
    E --> D[analyzer: resolved AST → mutants]
    D --> V[viability check: non-compiling mutants filtered]
    V --> F[schemata build, one per beamline]
    F --> G[per exposure: mutant x test, cheapest first, first kill wins]
    G --> H[TCE pass over survivors]
    H --> I[reports + criticality gate]
```

| ADR | Title | Status |
|---|---|---|
| [0001](0001-implement-in-dart.md) | Implement in Dart | accepted |
| [0002](0002-parse-with-official-analyzer.md) | Parse with the official analyzer | accepted |
| [0003](0003-distribution-and-sdk-resolution.md) | Distribution and SDK resolution | accepted |
| [0004](0004-shadow-copy-isolation.md) | Containment isolation | accepted |
| [0005](0005-mandatory-baseline-verification.md) | Mandatory background reading | accepted |
| [0006](0006-outcome-taxonomy.md) | Outcome taxonomy | accepted |
| [0007](0007-deterministic-execution.md) | Deterministic execution | accepted |
| [0008](0008-composable-mutator-framework.md) | Composable mutagen framework | accepted |
| [0009](0009-stryker-json-primary-report.md) | Stryker JSON as primary report | accepted |
| [0010](0010-mutant-schemata.md) | Mutant schemata | accepted, planned v1.0 |
| [0011](0011-per-test-coverage-routing.md) | Tracer coverage routing | accepted, staged v0.1-v1.0 |
| [0012](0012-tce-equivalent-detection.md) | TCE equivalent-mutant detection | accepted, planned v2.0 |
| [0013](0013-score-and-honesty-metrics.md) | Score and honesty metrics | accepted |
| [0014](0014-naming-and-vocabulary.md) | Naming and vocabulary | accepted |
| [0015](0015-full-pana-score.md) | Full pana score | accepted |
| [0016](0016-wide-event-logging.md) | Wide-event logging | accepted |
| [0017](0017-parallel-classification.md) | Parallel classification | accepted |
| [0018](0018-run-workspace-lifecycle.md) | Run workspace lifecycle | accepted, staged v0.1–v0.2 |
| [0019](0019-static-viability-filtering.md) | Static viability filtering | accepted |
| [0020](0020-zero-setup-provisioning.md) | Zero-setup provisioning | accepted, staged v0.1-v0.2 |
| [0021](0021-beamline-execution.md) | Beamline execution | accepted, planned v1.0 |
| [0022](0022-process-interlock.md) | Process interlock | accepted |

Feature staging: [../roadmap/index.md](../roadmap/index.md).
