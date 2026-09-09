# Changelog

## 0.2.0

- Irradiate pub workspace members by containing the whole workspace while
  keeping mutation, tests, coverage, reports, and member exclusions rooted at
  the selected package.

## 0.1.0

- `rad` CLI: irradiates `lib/`, prints per-outcome counts, MSI, and
  covered-code MSI, and writes a Stryker JSON report (`--output`).
- AST mutant generation with `package:analyzer`; mutagens for arithmetic,
  relational, equality, and logical operators plus boolean literals.
- Operator mutagens reject identity replacements and preserve valid division
  replacements in wider numeric contexts.
- Nullability mutagens: `a ?? b` mutates into always (`b`) and never (`a!`)
  falling back, `?.` access mutates into `!.`, and `null` is injected into
  declared-nullable returns, arguments, assignments, and initializers.
- Containment isolation of the project copy, with gitignore-style
  `.radignore` exclusions that also skip mutant generation; a red background
  reading aborts the run before generation and viability analysis.
- Outcome taxonomy: killed, survived, noCoverage, timeout, unviable, runError.
  Timeouts are inconclusive: they enter neither MSI term, and a timeout rate
  is printed when any occur.
- Gates: `--threshold` on the MSI, `--max-timeouts` on timed-out mutants. A
  run with no scoreable mutants reports no MSI and fails `--threshold`.
- `--coverage` ingests an `lcov.info`: mutants on lines no test hits report as
  `noCoverage` and never run.
- Zero setup: project dependencies are refreshed with `pub get`, a project's own
  `coverage/lcov.info` is picked up without `--coverage`, and otherwise
  coverage is collected in one extra suite run (`--no-collect-coverage`
  falls back to treating all code as covered).
- Mutant runs stop at the first failing test (`dart test --fail-fast`), so the
  project must resolve `package:test` 1.24.6 or newer.
- Collected coverage routes each mutant to the test files that cover it,
  cheapest first, in one run: a self-run of this package fell from hours to
  under two. A supplied `lcov.info` names no test files, so it still runs the
  whole suite per mutant.
- A timed-out suite is killed through a Windows job object, so everything it
  spawned dies with it in one call, detached processes included. Other
  platforms list the tree and sweep it until nothing new appears.
- A routed mutant is given the longer of its selection's own cost and the
  background reading, times three: workers contend, so a selection that runs
  serially is not a timed-out mutant.
- Static viability check: mutants that fail analysis (e.g. a flipped null
  check breaking type promotion) report as unviable without a test run.
- Promotion-aware guards: equality and logical mutagens skip flips whose
  stranded promotions could never compile, instead of reporting them.
- Parallel classification: `--jobs` workers, each with its own containment.
- Wide-event CLEF logging: one tool log, one run log per containment, each
  mutant's suite output kept as a capped excerpt while reporter events are
  parsed before the cap; `--verbose` renders ANSI-colored events on a terminal.
- Startup cleanup under an exclusive run lock; a held lock aborts the run,
  and every ordinary failure, including setup errors, releases its own lock.
- Keep containments and logs until the next run's startup cleanup.
- Allow `RAD_TEMP` to redirect the containment and log root.
