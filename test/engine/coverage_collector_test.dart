import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:radioactive_dart/src/engine/coverage_collector.dart';
import 'package:radioactive_dart/src/engine/suite_coverage_provider.dart';
import 'package:radioactive_dart/src/engine/run_aborted.dart';
import 'package:radioactive_dart/src/engine/test_runner.dart';
import 'package:radioactive_dart/src/model/test_run.dart';
import 'package:test/test.dart';

/// Writes [reports] into the coverage directory it is asked for, as an
/// instrumented suite run does.
final class _ReportingRunner implements TestRunner {
  _ReportingRunner(this.reports, {this.exitCode = 0, this.output = ''});

  /// Report file name to its `coverage` entries.
  final Map<String, List<Map<String, Object?>>> reports;
  final int exitCode;
  final String output;

  @override
  Future<TestRun> run({
    List<String> suites = const [],
    Duration? timeout,
    bool failFast = false,
    String? coverageDir,
  }) async {
    for (final entry in reports.entries) {
      File(p.join(coverageDir!, 'test', entry.key))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'type': 'CodeCoverage', 'coverage': entry.value}),
        );
    }
    return TestRun(
      exitCode: exitCode,
      timedOut: false,
      output: output,
      duration: const Duration(seconds: 1),
    );
  }
}

Map<String, Object?> _entry(String source, List<int> hits) => {
  'source': source,
  'script': <String, Object?>{},
  'hits': hits,
};

void main() {
  late Directory containment;
  late String coverageDir;

  Future<SuiteCoverageProvider> collect(
    Map<String, List<Map<String, Object?>>> reports,
  ) => CoverageCollector(
    root: containment.path,
    outputDir: coverageDir,
  ).collect(_ReportingRunner(reports));

  setUp(() async {
    containment = await Directory.systemTemp.createTemp('rad_collect_');
    addTearDown(() => containment.delete(recursive: true));
    coverageDir = p.join(containment.path, 'coverage');
    void write(String relative) => File(p.join(containment.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('');

    write('lib/calc.dart');
    write('lib/other.dart');
    write('test/calc_test.dart');
    File(p.join(containment.path, '.dart_tool', 'package_config.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'fixture', 'rootUri': '../', 'packageUri': 'lib/'},
            {
              'name': 'test',
              'rootUri': Uri.file(Directory.systemTemp.path).toString(),
              'packageUri': 'lib/',
            },
          ],
        }),
      );
  });

  test('resolves package: sources through the package config', () async {
    final provider = await collect({
      'calc_test.vm.json': [
        _entry('package:fixture/calc.dart', [1, 3, 2, 0]),
      ],
    });

    expect(provider.merged.hits, {
      'lib/calc.dart': {1: 3, 2: 0},
    });
  });

  test('resolves file: sources directly', () async {
    final source = Uri.file(
      p.join(containment.path, 'test', 'calc_test.dart'),
    ).toString();

    final provider = await collect({
      'calc_test.vm.json': [
        _entry(source, [4, 1]),
      ],
    });

    expect(provider.merged.hits, {
      'test/calc_test.dart': {4: 1},
    });
  });

  test('merges the counts a file collects across suites', () async {
    final provider = await collect({
      'a_test.vm.json': [
        _entry('package:fixture/calc.dart', [1, 2, 2, 0]),
      ],
      'b_test.vm.json': [
        _entry('package:fixture/calc.dart', [1, 5, 3, 1]),
      ],
    });

    expect(provider.merged.hits, {
      'lib/calc.dart': {1: 7, 2: 0, 3: 1},
    });
  });

  test('drops sources outside the containment', () async {
    final provider = await collect({
      'calc_test.vm.json': [
        _entry('package:test/test.dart', [1, 1]),
        _entry('package:unknown/thing.dart', [1, 1]),
        _entry(
          Uri.file(p.join(Directory.systemTemp.path, 'kernel.dill')).toString(),
          [1, 1],
        ),
        _entry('package:fixture/gone.dart', [1, 1]),
        _entry('org-dartlang-sdk:///sdk/lib/core.dart', [1, 1]),
        _entry('package:fixture/other.dart', [1, 1]),
      ],
    });

    expect(provider.merged.hits, {
      'lib/other.dart': {1: 1},
    });
  });

  test('counts what a non-VM suite reports', () async {
    final provider = await collect({
      'calc_test.chrome.json': [
        _entry('package:fixture/calc.dart', [1, 2]),
      ],
    });

    expect(provider.merged.hits, {
      'lib/calc.dart': {1: 2},
    });
  });

  test(
    'resolves a member package through a workspace package config',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'rad_collect_workspace_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final member = Directory(p.join(workspace.path, 'packages', 'member'))
        ..createSync(recursive: true);
      File(p.join(member.path, 'lib', 'calc.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('int get value => 1;\n');
      File(p.join(workspace.path, '.dart_tool', 'package_config.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'configVersion': 2,
            'packages': [
              {
                'name': 'fixture',
                'rootUri': '../packages/member',
                'packageUri': 'lib/',
              },
            ],
          }),
        );
      final output = p.join(member.path, 'coverage');

      final provider =
          await CoverageCollector(
            root: member.path,
            packageConfigRoot: workspace.path,
            outputDir: output,
          ).collect(
            _ReportingRunner({
              'calc_test.vm.json': [
                _entry('package:fixture/calc.dart', [1, 2]),
              ],
            }),
          );

      expect(provider.merged.hits, {
        'lib/calc.dart': {1: 2},
      });
    },
  );

  test('aborts when a green run records nothing', () async {
    await expectLater(
      collect({
        'calc_test.vm.json': [
          _entry('package:test/test.dart', [1, 1]),
        ],
      }),
      throwsA(
        isA<RunAborted>().having(
          (abort) => abort.message,
          'message',
          allOf(
            contains('recorded nothing'),
            contains('--no-collect-coverage'),
          ),
        ),
      ),
      reason: 'an unmeasured run must not pass as fully uncovered code',
    );
  });

  test('aborts when the instrumented run fails', () async {
    await expectLater(
      CoverageCollector(
        root: containment.path,
        outputDir: coverageDir,
      ).collect(_ReportingRunner(const {}, exitCode: 1, output: 'boom')),
      throwsA(
        isA<RunAborted>().having(
          (abort) => abort.message,
          'message',
          allOf(contains('exit 1'), contains('--no-collect-coverage')),
        ),
      ),
    );
  });
}
