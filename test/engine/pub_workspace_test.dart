import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:radioactive_dart/src/engine/pub_workspace.dart';
import 'package:radioactive_dart/src/engine/run_aborted.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspaceRoot;
  late Directory projectRoot;
  late File reference;

  setUp(() async {
    workspaceRoot = await Directory.systemTemp.createTemp('rad_workspace_');
    addTearDown(() => workspaceRoot.delete(recursive: true));
    File(p.join(workspaceRoot.path, 'pubspec.yaml'))
        .writeAsStringSync('name: fixture_workspace\n');
    projectRoot = Directory(p.join(workspaceRoot.path, 'packages', 'member'))
      ..createSync(recursive: true);
    File(p.join(projectRoot.path, 'pubspec.yaml'))
        .writeAsStringSync('name: fixture_member\n');
    reference = File(
      p.join(projectRoot.path, '.dart_tool', 'pub', 'workspace_ref.json'),
    );
  });

  void writeReference(Object? contents) {
    reference
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(contents));
  }

  Matcher abortsWith(String condition) => throwsA(
    isA<RunAborted>().having(
      (abort) => abort.message,
      'message',
      allOf(contains(reference.path), contains(condition)),
    ),
  );

  test('uses the selected package when no workspace reference exists', () {
    final workspace = PubWorkspace.resolve(p.join(projectRoot.path, '.'));

    expect(workspace.projectRoot, p.normalize(p.absolute(projectRoot.path)));
    expect(workspace.root, workspace.projectRoot);
  });

  test('resolves a pub-authored workspace root relative to its reference', () {
    writeReference({'workspaceRoot': '../../../..'});

    final workspace = PubWorkspace.resolve(projectRoot.path);

    expect(workspace.projectRoot, p.normalize(p.absolute(projectRoot.path)));
    expect(workspace.root, p.normalize(p.absolute(workspaceRoot.path)));
  });

  test('rejects malformed workspace reference JSON', () {
    reference
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{');

    expect(() => PubWorkspace.resolve(projectRoot.path), abortsWith('JSON'));
  });

  for (final invalid in <Object?>[
    const <String, Object?>{},
    const <String, Object?>{'workspaceRoot': 42},
  ]) {
    test('rejects a missing or non-string workspaceRoot: $invalid', () {
      writeReference(invalid);

      expect(
        () => PubWorkspace.resolve(projectRoot.path),
        abortsWith('missing or is not a string'),
      );
    });
  }

  test('rejects a workspace root without a pubspec', () {
    File(p.join(workspaceRoot.path, 'pubspec.yaml')).deleteSync();
    writeReference({'workspaceRoot': '../../../..'});

    expect(
      () => PubWorkspace.resolve(projectRoot.path),
      abortsWith('has no pubspec.yaml'),
    );
  });

  test('rejects a workspace root outside the package ancestry', () async {
    final outside = await Directory.systemTemp.createTemp(
      'rad_outside_workspace_',
    );
    addTearDown(() => outside.delete(recursive: true));
    File(p.join(outside.path, 'pubspec.yaml'))
        .writeAsStringSync('name: outside\n');
    writeReference({'workspaceRoot': outside.path});

    expect(
      () => PubWorkspace.resolve(projectRoot.path),
      abortsWith('outside the selected package ancestry'),
    );
  });
}
