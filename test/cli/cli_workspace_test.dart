@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:radioactive_dart/src/cli/cli.dart';
import 'package:radioactive_dart/src/rad_paths.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';
import '../helpers/paths.dart';

void main() {
  late RadPaths paths;

  setUp(() async => paths = await isolatedRadPaths('rad_cli_workspace_'));

  test('irradiates only the selected workspace member', () async {
    final fixture = await createFixtureWorkspace();
    final memberSource = File(p.join(fixture.member.path, 'lib', 'calc.dart'));
    final siblingSource = File(
      p.join(fixture.sibling.path, 'lib', 'value.dart'),
    );
    final originalMember = memberSource.readAsBytesSync();
    final originalSibling = siblingSource.readAsBytesSync();
    final out = StringBuffer();

    final exit = await radMain(
      ['--jobs', '1', '--output', 'report.json', fixture.member.path],
      out: out,
      paths: paths,
    );

    expect(exit, 0, reason: out.toString());
    expect(out.toString(), contains('MSI: 100.00%'));
    expect(out.toString(), contains('Covered-code MSI: 100.00%'));
    final report = jsonDecode(
      File(p.join(fixture.member.path, 'report.json')).readAsStringSync(),
    ) as Map<String, dynamic>;
    expect((report['files'] as Map<String, dynamic>).keys, ['lib/calc.dart']);
    expect(memberSource.readAsBytesSync(), originalMember);
    expect(siblingSource.readAsBytesSync(), originalSibling);
  });

  test('resolves sibling packages inside every containment', () async {
    final fixture = await createFixtureWorkspace();
    final memberSource = File(p.join(fixture.member.path, 'lib', 'calc.dart'));
    final siblingSource = File(
      p.join(fixture.sibling.path, 'lib', 'value.dart'),
    );
    final originalMember = memberSource.readAsBytesSync();
    final originalSibling = siblingSource.readAsBytesSync();
    final out = StringBuffer();

    final exit = await radMain(
      ['--jobs', '1', '--output', 'report.json', fixture.member.path],
      out: out,
      paths: paths,
    );

    expect(exit, 0, reason: out.toString());
    expect(out.toString(), contains('MSI: 100.00%'));
    final containments = Directory(paths.root)
        .listSync()
        .whereType<Directory>()
        .where(
          (directory) => p.basename(directory.path).startsWith('containment_'),
        )
        .toList();
    expect(containments, isNotEmpty);
    for (final containment in containments) {
      final copiedMember = p.join(containment.path, 'packages', 'member');
      final copiedSibling = p.join(containment.path, 'packages', 'sibling');
      expect(
        File(p.join(containment.path, 'pubspec.yaml')).existsSync(),
        isTrue,
      );
      expect(File(p.join(copiedMember, 'pubspec.yaml')).existsSync(), isTrue);
      expect(File(p.join(copiedSibling, 'pubspec.yaml')).existsSync(), isTrue);

      final config = File(
        p.join(containment.path, '.dart_tool', 'package_config.json'),
      );
      expect(config.existsSync(), isTrue);
      final decoded =
          jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
      final packages = decoded['packages'] as List<dynamic>;
      for (final name in ['fixture', 'rad_fixture_sibling']) {
        final package = packages.cast<Map<String, dynamic>>().singleWhere(
          (entry) => entry['name'] == name,
        );
        final resolved = Uri.file(config.path)
            .resolve(package['rootUri'] as String)
            .toFilePath();
        expect(
          p.isWithin(
            Directory(containment.path).resolveSymbolicLinksSync(),
            Directory(resolved).resolveSymbolicLinksSync(),
          ),
          isTrue,
          reason: '$name must resolve inside ${containment.path}',
        );
      }

      final reference = File(
        p.join(copiedMember, '.dart_tool', 'pub', 'workspace_ref.json'),
      );
      expect(reference.existsSync(), isTrue);
      final workspaceReference =
          jsonDecode(reference.readAsStringSync()) as Map<String, dynamic>;
      final referencedRoot = p.normalize(
        p.join(
          reference.parent.path,
          workspaceReference['workspaceRoot'] as String,
        ),
      );
      expect(p.equals(referencedRoot, containment.path), isTrue);
    }
    expect(memberSource.readAsBytesSync(), originalMember);
    expect(siblingSource.readAsBytesSync(), originalSibling);
  });
}
