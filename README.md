# radioactive_dart

Mutation testing for Dart. Irradiates `lib/` with mutants and scores which
ones the tests kill.

## Usage

- Run `dart run radioactive_dart:rad` in a project root.
- Prints per-outcome counts, MSI, and covered-code MSI.
- Timed-out mutants are inconclusive: they count as neither killed nor
  survived, and a timeout rate is printed whenever any occur.
- With no scoreable mutants there is no MSI: scores print as `none` and
  `--threshold` fails.
- Mutants no test reaches report as `noCoverage` without a run, which lowers
  the MSI but leaves the covered-code MSI intact. Coverage comes from, in
  order:

| Order | Condition | Source |
|---|---|---|
| 1 | `--coverage <path>` given | that `lcov.info` |
| 2 | `coverage/lcov.info` records something | that report |
| 3 | otherwise | rad collects it in one extra suite run |

- Coverage rad collects itself also routes: a mutant runs only against the
  test files that cover its line, cheapest first, in one `--fail-fast` run.
  An `lcov.info` names no test files, so rows 1 and 2 run the whole suite per
  mutant.
- `--no-collect-coverage` drops step 3 and treats all code as covered.
- A collection that fails or measures nothing aborts the run instead of
  guessing; rerun with `--no-collect-coverage`.
- Writes a Stryker JSON report (`mutation-report.json`); view it with the
  [Stryker report viewer](https://microsoft.github.io/mutation-testing-elements/).

| Flag | Effect | Default |
|---|---|---|
| `-c, --coverage` | `lcov.info` to route from; unhit lines are not run | None |
| `--[no-]collect-coverage` | Collect coverage when no report is given or found | `true` |
| `-t, --threshold` | Exit 1 when the MSI is below this percentage (0-100) | None |
| `--max-timeouts` | Exit 1 when more mutants than this time out | None |
| `-o, --output` | Report path, relative to the project root | `mutation-report.json` |
| `-j, --jobs` | Parallel workers, each with its own containment copy | Half the CPU cores |
| `-v, --verbose` | Also stream structured log events to the console | Off |

- Exit codes: 0 success, 1 gate failed, 64 usage, 70 aborted run.
- A red test suite aborts the run; a green suite is a precondition.
- The project must resolve `package:test` 1.24.6 or newer; older versions
  abort the run.
- Project dependencies are resolved first: rad runs `dart pub get`, refreshing
  stale configuration or writing `pubspec.lock` and `.dart_tool/` when absent.
- Selecting a pub workspace member copies the whole pub workspace into each
  containment. Tests, mutation generation, coverage paths, report output, and
  the member's `.radignore` stay rooted at the selected member.
- A workspace root `.radignore` prunes workspace-relative paths from the larger
  copy. Excluding a file the member needs fails the green background reading.
- `.radignore` (gitignore-style rules incl. negation and directory patterns,
  project root) excludes paths from the isolated project copy tests run in.
  An excluded directory is never descended into, so `!` cannot re-include a
  file below it, just like git.
- All temp data (containment copies, logs) lives under one rad temp root.
- The default root is `<system temp>/rad/`; `RAD_TEMP` redirects it to an exact
  path.
- A run takes an exclusive `<rad temp root>/.lock`, then clears what earlier
  runs left there. A run that finds the lock held aborts with exit 70 instead
  of touching the other run's state; only a run killed outright leaves the
  lock behind.
- Each run writes wide-event CLEF logs to `<rad temp root>/rad.log`,
  replacing the previous run's file. A 32 KiB head-and-tail excerpt of every
  executed mutant's suite output is kept in `<rad temp root>/runs/`, one log
  per worker named after its containment. The folder remains present; a new
  run clears only its previous contents. Nested engine runs cannot clear or overwrite the active tool run's
  files.

## Windows performance

- Antivirus scanning of containment copies can significantly slow testing.
- Set a dedicated root before running rad:
  `$env:RAD_TEMP = 'D:\temp\rad'`.
- If policy permits, exclude only that dedicated directory from antivirus
  scanning. Do not exclude the whole system temp directory.

## More

- Documentation: [docs/index.md](docs/index.md)
- Feature staging: [docs/roadmap/index.md](docs/roadmap/index.md)
- Decisions: [docs/decisions/index.md](docs/decisions/index.md)
- `sandbox/`: spike playground, not part of the package
