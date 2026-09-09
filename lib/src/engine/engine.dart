import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../log/rad_logger.dart';
import '../model/mutant.dart';
import '../model/mutant_result.dart';
import '../model/outcome.dart';
import '../model/test_events.dart';
import '../model/test_run.dart';
import '../model/test_suite.dart';
import '../mutagens/mutagen_registry.dart';
import '../rad_paths.dart';
import 'containment.dart';
import 'coverage_collector.dart';
import 'coverage_provider.dart';
import 'dart_test_runner.dart';
import 'full_coverage_provider.dart';
import 'mutant_generator.dart';
import 'outcome_classifier.dart';
import 'pub_get.dart';
import 'pub_workspace.dart';
import 'rad_ignore.dart';
import 'run_aborted.dart';
import 'run_result.dart';
import 'test_runner.dart';
import 'test_version_check.dart';
import 'viability_checker.dart';

/// Called after each classified mutant with progress counters.
typedef ProgressCallback =
    void Function(int done, int total, MutantResult result);

/// Builds a runner rooted at a containment; [suiteConcurrency] is this
/// worker's share of the cores (ADR 0017).
typedef RunnerFactory = TestRunner Function(String root, int suiteConcurrency);

/// Orchestrates a full run: contain, verify, generate, irradiate, classify.
final class Engine {
  /// Creates an engine for the project at [projectRoot].
  Engine({
    required this.projectRoot,
    required this.paths,
    MutagenRegistry? registry,
    this.coverage = const FullCoverageProvider(),
    this.runnerFactory = _defaultRunnerFactory,
    this.onProgress,
    this.logger,
    int? jobs,
  }) : registry = registry ?? MutagenRegistry.defaults(),
       jobs = jobs ?? defaultJobs,
       runId =
           logger?.runId ??
           DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static TestRunner _defaultRunnerFactory(String root, int suiteConcurrency) =>
      DartTestRunner(root, concurrency: suiteConcurrency);

  /// Default worker count: half the cores, since each suite process
  /// parallelizes internally already (ADR 0017).
  static int get defaultJobs => max(1, Platform.numberOfProcessors ~/ 2);

  /// Absolute or relative path of the project under test.
  final String projectRoot;

  /// Filesystem locations resolved by the caller for this invocation.
  final RadPaths paths;

  /// The active mutagen set.
  final MutagenRegistry registry;

  /// Coverage seam; `null` collects coverage during the run (ADR 0020).
  final CoverageProvider? coverage;

  /// Builds the runner for a containment root; seam for `flutter test`.
  final RunnerFactory runnerFactory;

  /// Optional per-mutant progress hook, called in completion order.
  final ProgressCallback? onProgress;

  /// Number of parallel workers, each owning a containment (ADR 0017).
  final int jobs;

  /// Receives engine wide events; `null` disables engine logging.
  final RadLogger? logger;

  /// Correlates and namespaces every mutant-run log from this engine run.
  final String runId;

  /// Characters of each suite stream kept per mutant. The live stream stays
  /// generous so nothing is parsed truncated, but every mutant's excerpt is
  /// retained until the run ends (ADR 0016).
  static const outputExcerptLimit = 32 * 1024;

  /// Directory inside the baseline containment holding the collected VM
  /// coverage reports (ADR 0020).
  static const coverageDirName = '.rad_coverage';

  /// Outcomes recorded as errors in their run log.
  static const failedOutcomes = {
    Outcome.timeout,
    Outcome.unviable,
    Outcome.runError,
    Outcome.memoryError,
  };

  /// Runs the whole pipeline and returns every classified result.
  Future<RunResult> run() async {
    Directory(paths.runLogs).createSync(recursive: true);
    await _provision();
    final workspace = PubWorkspace.resolve(projectRoot);

    // Contain and verify before the expensive analysis stages so a red
    // suite aborts within the background reading's duration (ADR 0005).
    final prepareWatch = Stopwatch()..start();
    // Divide the cores among the requested jobs so parallel suites do not
    // oversubscribe; the background reading uses the same concurrency to
    // keep half-lives calibrated (ADR 0017).
    final suiteConcurrency = max(1, Platform.numberOfProcessors ~/ jobs);
    final ignore = RadIgnore.load(projectRoot);
    final baseline = await Containment.create(
      projectRoot,
      paths: paths,
      ignore: ignore,
      workspaceRoot: workspace.root,
      workspaceIgnore: RadIgnore.load(workspace.root),
    );
    await pubGet(baseline.projectRoot, label: 'the containment');
    ensureTestVersion(baseline.root);
    // One pristine clone before the background reading; the workers are cloned
    // from it, so none inherits what that suite writes into the package tree
    // (ADR 0017) and a red reading still costs one extra copy (ADR 0005).
    final template = await baseline.clone();
    prepareWatch.stop();

    final background = await runnerFactory(
      baseline.projectRoot,
      suiteConcurrency,
    ).run();
    if (background.exitCode != 0) {
      final summary = (background.events ?? TestEvents.parse(background.output))
          .summarize();
      final evidence = summary.isEmpty
          ? '${background.output}${background.errorOutput}'
          : summary;
      throw RunAborted(
        'background reading is red; a green suite is a precondition '
        '(ADR 0005). If a copy exclusion removed a required asset, fix '
        '$containmentIgnoreFile.\n'
        '$evidence',
      );
    }
    final halfLife = halfLifeFor(background.duration);
    logger?.info(
      'background reading green in {DurationMs} ms, '
      'half-life {HalfLifeMs} ms',
      {
        'DurationMs': background.duration.inMilliseconds,
        'HalfLifeMs': halfLife.inMilliseconds,
      },
    );

    final routing = await _resolveCoverage(baseline);
    final (mutants, sources, unviable) = await _generate(ignore, routing);

    prepareWatch.start();
    final workers = max(1, min(jobs, mutants.length));
    final containments = [
      template,
      ...await Future.wait([
        for (var i = 1; i < workers; i++) template.clone(),
      ]),
    ];
    final runners = [
      for (final c in containments)
        runnerFactory(c.projectRoot, suiteConcurrency),
    ];
    prepareWatch.stop();
    logger?.info(
      'prepared {Containments} containments in {DurationMs} ms, '
      '{SuiteConcurrency} test threads each',
      {
        'Containments': containments.length,
        'SuiteConcurrency': suiteConcurrency,
        'DurationMs': prepareWatch.elapsedMilliseconds,
      },
    );
    // One run log per containment, named after it (ADR 0016).
    final runLogs = [
      for (final c in containments)
        RadLogger(
          verbose: false,
          path: p.join(paths.runLogs, '${c.name}.log'),
          runId: runId,
        ),
    ];

    // One shared queue; results keyed by index so completion order never
    // changes the report (ADR 0007, ADR 0017).
    final results = List<MutantResult?>.filled(mutants.length, null);
    var next = 0;
    var done = 0;
    Future<void> worker(int slot) async {
      while (true) {
        final index = next++;
        if (index >= mutants.length) return;
        final result = await _classify(
          mutants[index],
          containments[slot],
          runners[slot],
          runLogs[slot],
          halfLife,
          unviable,
          routing,
        );
        results[index] = result;
        done++;
        logger?.info('classified {MutantId} as {Outcome} ({Done}/{Total})', {
          'MutantId': result.mutant.id,
          'Outcome': result.outcome.name,
          'Done': done,
          'Total': mutants.length,
          'Worker': slot,
          'Containment': containments[slot].name,
          'File': result.mutant.mutation.filePath,
          'Offset': result.mutant.mutation.offset,
          'Operator': result.mutant.mutation.operatorId,
          'Replacement': result.mutant.mutation.replacement,
          'ExitCode': result.testRun?.exitCode,
          'TimedOut': result.testRun?.timedOut,
          'DurationMs': result.testRun?.duration.inMilliseconds,
        });
        onProgress?.call(done, mutants.length, result);
      }
    }

    await Future.wait([for (var i = 0; i < workers; i++) worker(i)]);
    return RunResult(
      results: results.cast<MutantResult>(),
      sources: sources,
      backgroundReading: background.duration,
      halfLife: halfLife,
    );
  }

  /// Every mutant with its file's pristine source, plus the ids of those that
  /// fail static analysis: a non-compiling mutant needs no evidence from the
  /// suite (ADR 0019).
  ///
  /// The analyzer state lives and dies inside this method, so its resolved
  /// units are collectible before the first worker runs (ADR 0016).
  Future<(List<Mutant>, Map<String, String>, Set<String>)> _generate(
    RadIgnore ignore,
    CoverageProvider coverage,
  ) async {
    final watch = Stopwatch()..start();
    final generator = MutantGenerator(
      projectRoot: projectRoot,
      registry: registry,
      ignore: ignore,
    );
    final (mutants, sources) = await generator.generate();
    coverage.indexSources(sources);
    final perFile = <String, int>{for (final file in sources.keys) file: 0};
    for (final mutant in mutants) {
      perFile.update(mutant.mutation.filePath, (count) => count + 1);
    }
    perFile.forEach(
      (file, count) => logger?.info('found {MutantCount} mutants in {File}', {
        'MutantCount': count,
        'File': file,
      }),
    );
    logger?.info(
      'generated {MutantCount} mutants in {FileCount} files in {DurationMs} ms',
      {
        'MutantCount': mutants.length,
        'FileCount': sources.length,
        'DurationMs': watch.elapsedMilliseconds,
      },
    );

    watch.reset();
    final unviable = await ViabilityChecker(
      analysis: generator.analysis,
    ).unviable(mutants.where(coverage.isCovered), sources);
    logger?.info(
      'checked viability of {MutantCount} mutants in {DurationMs} ms; '
      '{UnviableCount} unviable',
      {
        'MutantCount': mutants.length,
        'UnviableCount': unviable.length,
        'DurationMs': watch.elapsedMilliseconds,
      },
    );
    return (mutants, sources, unviable);
  }

  Future<MutantResult> _classify(
    Mutant mutant,
    Containment containment,
    TestRunner runner,
    RadLogger runLog,
    Duration halfLife,
    Set<String> unviable,
    CoverageProvider coverage,
  ) async {
    if (!coverage.isCovered(mutant)) {
      return MutantResult(mutant: mutant, outcome: Outcome.noCoverage);
    }
    if (unviable.contains(mutant.id)) {
      return MutantResult(mutant: mutant, outcome: Outcome.unviable);
    }
    try {
      await containment.apply(mutant.mutation);
      // Only the suites covering the mutant, cheapest first, in one
      // fail-fast run: the first failure ends it, so an early kill costs the
      // cheap suites only (ADR 0011). An unknown selection runs everything.
      final suites = coverage.suitesFor(mutant);
      final run = await runner.run(
        suites: [for (final suite in suites ?? const <TestSuite>[]) suite.path],
        timeout: _halfLifeFor(suites, halfLife),
        // One failing test already kills the mutant; the rest is wasted work.
        failFast: true,
      );
      // The whole stream is parsed once here and dropped afterwards; only an
      // excerpt outlives this classification (ADR 0016).
      final events = run.events ?? TestEvents.parse(run.output);
      final result = MutantResult(
        mutant: mutant,
        outcome: const OutcomeClassifier().classify(run, events),
        testRun: _excerpt(run),
      );
      _logMutantRun(runLog, containment.name, result, events.errors, suites);
      return result;
      // Expected mutant-level failures are outcomes, never exceptions
      // (ADR 0006); their evidence lands in the run log (ADR 0016).
    } catch (error, stackTrace) {
      if (error is! IOException && error is! StateError) rethrow;
      final result = MutantResult(
        mutant: mutant,
        outcome: Outcome.runError,
        error: '$error\n$stackTrace',
      );
      _logMutantRun(runLog, containment.name, result, const [], null);
      return result;
    } finally {
      await containment.restore(mutant.mutation.filePath);
    }
  }

  /// Copy of [run] keeping only a bounded excerpt of each stream, since every
  /// mutant's result lives until the run ends (ADR 0016).
  static TestRun _excerpt(TestRun run) => TestRun(
    exitCode: run.exitCode,
    timedOut: run.timedOut,
    output: _cap(run.output),
    errorOutput: _cap(run.errorOutput),
    duration: run.duration,
  );

  static String _cap(String stream) {
    if (stream.length <= outputExcerptLimit) return stream;
    const head = outputExcerptLimit ~/ 2;
    return '${stream.substring(0, head)}\n'
        '[rad] truncated ${stream.length - outputExcerptLimit} characters\n'
        '${stream.substring(stream.length - outputExcerptLimit + head)}';
  }

  /// Appends one wide event for [result] to its worker's [runLog],
  /// correlated with the tool log through the shared `RunId` (ADR 0016).
  /// [nestedErrors] come from the full stream, of which [result] keeps only
  /// an excerpt.
  void _logMutantRun(
    RadLogger runLog,
    String containment,
    MutantResult result,
    List<String> nestedErrors,
    List<TestSuite>? suites,
  ) {
    final run = result.testRun;
    final mutation = result.mutant.mutation;
    final properties = {
      'MutantId': result.mutant.id,
      'Containment': containment,
      'Outcome': result.outcome.name,
      'Mutation': mutation.description,
      'File': mutation.filePath,
      'Offset': mutation.offset,
      'Operator': mutation.operatorId,
      'Replacement': mutation.replacement,
      'Suites': [for (final suite in suites ?? const <TestSuite>[]) suite.path],
      'SuiteMs': suites?.fold(
        0,
        (total, s) => total + s.duration.inMilliseconds,
      ),
      if (result.error != null) 'Error': result.error,
      if (run != null) ...{
        'ExitCode': run.exitCode,
        'TimedOut': run.timedOut,
        'DurationMs': run.duration.inMilliseconds,
        'Output': run.output,
        'ErrorOutput': run.errorOutput,
      },
    };
    if (failedOutcomes.contains(result.outcome)) {
      runLog.error('mutant run failed: {MutantId} as {Outcome}', properties);
    } else {
      runLog.info('mutant run completed: {MutantId} as {Outcome}', properties);
    }
    for (final error in nestedErrors) {
      runLog.error('nested test error: {Error}', {'Error': error});
    }
  }

  /// Half-life of a routed run: whichever of the selection's own serial cost
  /// and the [wholeSuite] reading is longer, both on the `× 3` rule.
  ///
  /// Workers contend for the machine, so a routed run cannot count on the
  /// parallelism the background reading measured; its suites effectively run
  /// one after another. Taking the reading alone timed out 75 of 709 healthy
  /// mutants (2026-08-21), 31 of them routed to the whole suite.
  static Duration _halfLifeFor(List<TestSuite>? suites, Duration wholeSuite) {
    if (suites == null) return wholeSuite;
    final selected = halfLifeFor(
      suites.fold(Duration.zero, (total, suite) => total + suite.duration),
    );
    return selected > wholeSuite ? selected : wholeSuite;
  }

  /// Per-mutant timeout: `max(background × 3, 10 s floor)` (ADR 0006).
  static Duration halfLifeFor(Duration background) {
    const floor = Duration(seconds: 10);
    final scaled = background * 3;
    return Duration(
      microseconds: max(scaled.inMicroseconds, floor.inMicroseconds),
    );
  }

  /// Resolves the project before it is copied or analysed: a stale package
  /// configuration would otherwise yield only unviable mutants (ADR 0020).
  Future<void> _provision() async {
    // A missing or non-package root reports better from the copy and
    // containment stages than from `pub get` here.
    if (!File(p.join(projectRoot, 'pubspec.yaml')).existsSync()) return;
    final watch = Stopwatch()..start();
    await pubGet(projectRoot, label: 'the project');
    logger?.info('provisioned {ProjectRoot} in {DurationMs} ms', {
      'ProjectRoot': projectRoot,
      'DurationMs': watch.elapsedMilliseconds,
    });
  }

  /// The routing coverage: the supplied provider, or one collected by an
  /// extra instrumented run of the green suite (ADR 0020). It reuses the
  /// baseline containment, which the workers no longer clone from, so none
  /// of them inherits the coverage artefacts.
  Future<CoverageProvider> _resolveCoverage(Containment baseline) async {
    final supplied = coverage;
    if (supplied != null) return supplied;
    final watch = Stopwatch()..start();
    // Nothing else runs during collection and its duration calibrates
    // nothing, so it uses every core instead of one job's share.
    final collected = await CoverageCollector(
      root: baseline.projectRoot,
      packageConfigRoot: baseline.root,
      outputDir: p.join(baseline.projectRoot, coverageDirName),
    ).collect(runnerFactory(baseline.projectRoot, Platform.numberOfProcessors));
    logger
        ?.info('collected coverage for {FileCount} files in {DurationMs} ms', {
          'FileCount': collected.merged.hits.length,
          'DurationMs': watch.elapsedMilliseconds,
        });
    return collected;
  }
}
