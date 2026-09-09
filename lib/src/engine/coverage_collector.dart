import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/test_events.dart';
import 'lcov_coverage_provider.dart';
import 'run_aborted.dart';
import 'suite_coverage_provider.dart';
import 'test_runner.dart';

/// Collects per-line coverage from one instrumented suite run (ADR 0020).
final class CoverageCollector {
  /// Collects inside the containment at [root]; the suite writes its per-suite
  /// reports into [outputDir]. [packageConfigRoot] may name a containing pub
  /// workspace; it defaults to [root] for a single package.
  CoverageCollector({
    required this.root,
    required this.outputDir,
    String? packageConfigRoot,
  }) : packageConfigRoot = packageConfigRoot ?? root;

  /// Selected package root every collected path is relativized against.
  final String root;

  /// Root whose `.dart_tool/package_config.json` resolves package URIs.
  final String packageConfigRoot;

  /// Directory `dart test --coverage` writes its per-suite reports into.
  final String outputDir;

  /// Runs the whole suite through [runner] and returns what it recorded,
  /// keyed by project-relative posix path and by the suite that recorded it.
  Future<SuiteCoverageProvider> collect(TestRunner runner) async {
    final run = await runner.run(coverageDir: outputDir);
    if (run.exitCode != 0) {
      // Falling back to full coverage would inflate the score (ADR 0013).
      final summary = (run.events ?? TestEvents.parse(run.output)).summarize();
      throw RunAborted(
        'coverage collection failed with exit ${run.exitCode}; rerun with '
        '--no-collect-coverage to treat all code as covered.\n'
        '${summary.isEmpty ? run.errorOutput : summary}',
      );
    }
    final perSuite = _read();
    final hits = <String, Map<int, int>>{};
    for (final files in perSuite.values) {
      files.forEach((file, lines) {
        final merged = hits.putIfAbsent(file, () => {});
        lines.forEach(
          (line, count) =>
              merged.update(line, (sum) => sum + count, ifAbsent: () => count),
        );
      });
    }
    if (hits.isEmpty) {
      // A green suite always records the sources it loaded, so an empty
      // result means the measurement failed, not that nothing is covered;
      // routing on it would report every mutant as `noCoverage` (ADR 0020).
      throw RunAborted(
        'coverage collection recorded nothing; rerun with '
        '--no-collect-coverage to treat all code as covered.',
      );
    }
    return SuiteCoverageProvider(
      merged: LcovCoverageProvider(hits: hits),
      perSuite: {
        for (final entry in perSuite.entries)
          entry.key: {
            for (final file in entry.value.entries)
              file.key: {
                for (final line in file.value.entries)
                  if (line.value > 0) line.key,
              },
          },
      },
      durations: (run.events ?? TestEvents.parse(run.output)).suiteDurations,
      wholeRun: run.duration,
    );
  }

  /// Every emitted report, by the suite that wrote it: one file can be
  /// recorded by several suites (ADR 0011).
  Map<String, Map<String, Map<int, int>>> _read() {
    final perSuite = <String, Map<String, Map<int, int>>>{};
    final reports = Directory(outputDir);
    if (!reports.existsSync()) return perSuite;
    final packages = _packageLibraries();
    final realRoot = Directory(root).resolveSymbolicLinksSync();
    for (final file in reports.listSync(recursive: true).whereType<File>()) {
      // Each report is named `<suite>.<runtime>.json`; every runtime writes
      // the same hit map, so a non-VM suite counts too (ADR 0020).
      if (!file.path.endsWith('.json')) continue;
      final report = jsonDecode(file.readAsStringSync());
      if (report is! Map<String, dynamic>) continue;
      final hits = perSuite.putIfAbsent(_suiteOf(file.path), () => {});
      for (final entry in report['coverage'] as List<dynamic>? ?? const []) {
        if (entry is! Map<String, dynamic>) continue;
        final source = entry['source'];
        final path = source is String
            ? _relative(source, packages, realRoot)
            : null;
        if (path == null) continue;
        final lines = hits.putIfAbsent(path, () => {});
        final counts = entry['hits'] as List<dynamic>? ?? const [];
        for (var i = 0; i + 1 < counts.length; i += 2) {
          final count = counts[i + 1] as int;
          lines.update(
            counts[i] as int,
            (previous) => previous + count,
            ifAbsent: () => count,
          );
        }
      }
    }
    return perSuite;
  }

  /// Suite a report belongs to: `dart test` names each `<suite>.<runtime>.json`
  /// under the coverage directory.
  String _suiteOf(String reportPath) => p
      .withoutExtension(
        p.withoutExtension(p.relative(reportPath, from: outputDir)),
      )
      .replaceAll(r'\', '/');

  /// Containment-relative posix path of [source], or `null` when it is not a
  /// file inside the containment. Both sides are resolved through the
  /// filesystem: the SDK spells temp paths differently than rad created them.
  String? _relative(String source, Map<String, Uri> packages, String realRoot) {
    final uri = Uri.tryParse(source);
    final Uri? file;
    if (uri == null) {
      file = null;
    } else if (uri.scheme == 'package') {
      final segments = uri.pathSegments;
      file = segments.length < 2
          ? null
          : packages[segments.first]?.resolve(segments.skip(1).join('/'));
    } else {
      file = uri.scheme == 'file' ? uri : null;
    }
    if (file == null) return null;
    final String real;
    try {
      real = File(file.toFilePath()).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
    if (!p.isWithin(realRoot, real)) return null;
    return p.relative(real, from: realRoot).replaceAll(r'\', '/');
  }

  /// Each package's library directory, per the containment's package config.
  Map<String, Uri> _packageLibraries() {
    final file = File(
      p.join(packageConfigRoot, '.dart_tool', 'package_config.json'),
    );
    if (!file.existsSync()) return const {};
    final base = Uri.file(file.path);
    final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return {
      for (final package in config['packages'] as List<dynamic>? ?? const [])
        if (package case {
          'name': final String name,
          'rootUri': final String root,
        })
          name: base
              .resolve(_directory(root))
              .resolve(_directory(package['packageUri'] as String? ?? 'lib')),
    };
  }

  static String _directory(String uri) => uri.endsWith('/') ? uri : '$uri/';
}
