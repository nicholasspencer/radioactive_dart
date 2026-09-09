import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:radioactive_dart/radioactive_dart.dart';
import 'package:radioactive_dart/src/engine/containment.dart';
import 'package:radioactive_dart/src/engine/rad_ignore.dart';
import 'package:test/test.dart';

import '../helpers/paths.dart';

Future<Directory> fixtureProject() async {
  final dir = await Directory.systemTemp.createTemp('rad_containment_src_');
  addTearDown(() => dir.delete(recursive: true));
  void write(String relative, String content) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  write('lib/a.dart', 'int add(int a, int b) => a + b;\n');
  write('test/a_test.dart', 'void main() {}\n');
  write('.git/config', 'x');
  write('.dart_tool/package_config.json', '{}');
  write('build/out.txt', 'x');
  write('lib/nested/build/gen.dart', 'const g = 1;\n');
  write('tool/build', '#!/bin/sh\n');
  write('packages/sub/lib/b.dart', 'const b = 1;\n');
  write('packages/sub/.dart_tool/package_config.json', '{}');
  write('packages/sub/build/out.txt', 'x');
  write('packages/sub/.git/config', 'x');
  write('assets/big/blob.bin', 'x');
  write('assets/big/keep.txt', 'keep');
  write('assets/small.txt', 'keep');
  write('deep/nested/trace.log', 'x');
  write(
    '.radignore',
    '# comment\n\n*.log\nassets/big/**\n!assets/big/keep.txt\n',
  );
  return dir;
}

void main() {
  late Directory source;
  late RadPaths paths;
  late Containment containment;

  setUp(() async {
    source = await fixtureProject();
    paths = await isolatedRadPaths('rad_containment_state_');
    containment = await Containment.create(
      source.path,
      paths: paths,
      ignore: RadIgnore.load(source.path),
    );
  });

  test('lives inside the configured temp folder', () {
    expect(p.isWithin(paths.root, containment.root), isTrue);
  });

  test('copies the project without excluded paths', () {
    bool has(String relative) =>
        File(p.join(containment.root, relative)).existsSync();
    expect(has('lib/a.dart'), isTrue);
    expect(has('test/a_test.dart'), isTrue);
    expect(has('assets/small.txt'), isTrue);
    expect(has('.git/config'), isFalse);
    expect(has('.dart_tool/package_config.json'), isFalse);
    expect(has('build/out.txt'), isFalse);
    expect(has('assets/big/blob.bin'), isFalse);
    expect(has('assets/big/keep.txt'), isTrue);
    expect(has('deep/nested/trace.log'), isFalse);
  });

  test('prunes nested tooling directories only', () {
    bool has(String relative) =>
        File(p.join(containment.root, relative)).existsSync();
    expect(has('packages/sub/lib/b.dart'), isTrue);
    expect(has('packages/sub/.dart_tool/package_config.json'), isFalse);
    expect(has('packages/sub/.git/config'), isFalse);
    expect(has('packages/sub/build/out.txt'), isTrue);
    expect(has('lib/nested/build/gen.dart'), isTrue);
    expect(has('tool/build'), isTrue);
  });

  test('keeps a directory rule from being undone below it', () async {
    final project = await fixtureProject();
    File(
      p.join(project.path, '.radignore'),
    ).writeAsStringSync('assets/big/\n!assets/big/keep.txt\n');
    final copy = await Containment.create(
      project.path,
      paths: await isolatedRadPaths('rad_containment_rule_'),
      ignore: RadIgnore.load(project.path),
    );
    expect(Directory(p.join(copy.root, 'assets/big')).existsSync(), isFalse);
    expect(File(p.join(copy.root, 'assets/small.txt')).existsSync(), isTrue);
  });

  test('does not copy an in-project rad root', () async {
    final project = await fixtureProject();
    final inProject = RadPaths(root: p.join(project.path, '.rad_temp'));
    final copy = await Containment.create(
      project.path,
      paths: inProject,
      ignore: RadIgnore.load(project.path),
    );
    expect(Directory(p.join(copy.root, '.rad_temp')).existsSync(), isFalse);
    expect(File(p.join(copy.root, 'lib/a.dart')).existsSync(), isTrue);
  });

  test('copies the project when the rad root equals it', () async {
    final project = await fixtureProject();
    final copy = await Containment.create(
      project.path,
      paths: RadPaths(root: project.path),
      ignore: RadIgnore.load(project.path),
    );
    expect(File(p.join(copy.root, 'lib/a.dart')).existsSync(), isTrue);
    expect(Directory(p.join(copy.root, copy.name)).existsSync(), isFalse);
  });

  test('clones the copied tree into an independent containment', () async {
    File(p.join(containment.root, '.dart_tool/package_config.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"resolved": true}');
    final clone = await containment.clone();

    expect(p.isWithin(paths.root, clone.root), isTrue);
    expect(clone.root, isNot(containment.root));
    expect(
      File(
        p.join(clone.root, '.dart_tool/package_config.json'),
      ).readAsStringSync(),
      '{"resolved": true}',
    );

    const mutation = Mutation(
      filePath: 'lib/a.dart',
      offset: 27,
      length: 1,
      original: '+',
      replacement: '-',
      operatorId: 'arithmetic',
      description: 'replace + with -',
    );
    await clone.apply(mutation);
    expect(
      File(p.join(clone.root, 'lib/a.dart')).readAsStringSync(),
      contains('a - b'),
    );
    expect(
      File(p.join(containment.root, 'lib/a.dart')).readAsStringSync(),
      contains('a + b'),
    );

    await containment.apply(mutation);
    await containment.restore('lib/a.dart');
    expect(
      File(p.join(clone.root, 'lib/a.dart')).readAsStringSync(),
      contains('a - b'),
    );
  });

  test('copies a workspace while targeting only its member', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'rad_containment_workspace_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final member = Directory(p.join(workspace.path, 'packages', 'member'));
    void write(String relative, String contents) {
      final file = File(p.join(workspace.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    write('pubspec.yaml', 'name: workspace\n');
    write('.radignore', 'bulk/\n');
    write('bulk/blob.bin', 'workspace bulk');
    write('build/root.txt', 'root output');
    write('packages/member/pubspec.yaml', 'name: member\n');
    write('packages/member/.radignore', 'assets/\n');
    write('packages/member/lib/a.dart', 'int add(int a, int b) => a + b;\n');
    write('packages/member/assets/blob.bin', 'member bulk');
    write('packages/member/build/member.txt', 'member output');
    write('packages/member/.dart_tool/config.json', '{}');
    write('packages/sibling/lib/b.dart', 'const b = 1;\n');
    write('packages/sibling/build/kept.txt', 'sibling source');
    write('packages/sibling/.git/config', 'metadata');

    final copy = await Containment.create(
      member.path,
      workspaceRoot: workspace.path,
      workspaceIgnore: RadIgnore.load(workspace.path),
      paths: await isolatedRadPaths('rad_containment_workspace_state_'),
      ignore: RadIgnore.load(member.path),
    );

    expect(copy.projectRoot, p.join(copy.root, 'packages', 'member'));
    expect(File(p.join(copy.root, 'bulk', 'blob.bin')).existsSync(), isFalse);
    expect(File(p.join(copy.root, 'build', 'root.txt')).existsSync(), isFalse);
    expect(
      File(p.join(copy.projectRoot, 'assets', 'blob.bin')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(copy.projectRoot, 'build', 'member.txt')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(copy.projectRoot, '.dart_tool', 'config.json')).existsSync(),
      isFalse,
    );
    expect(
      File(
        p.join(copy.root, 'packages', 'sibling', 'lib', 'b.dart'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(copy.root, 'packages', 'sibling', 'build', 'kept.txt'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(copy.root, 'packages', 'sibling', '.git', 'config'),
      ).existsSync(),
      isFalse,
    );

    const mutation = Mutation(
      filePath: 'lib/a.dart',
      offset: 27,
      length: 1,
      original: '+',
      replacement: '-',
      operatorId: 'arithmetic',
      description: 'replace + with -',
    );
    await copy.apply(mutation);
    expect(
      File(p.join(copy.projectRoot, 'lib', 'a.dart')).readAsStringSync(),
      contains('a - b'),
    );
    await copy.restore(mutation.filePath);

    final clone = await copy.clone();
    expect(clone.projectRoot, p.join(clone.root, 'packages', 'member'));
    expect(
      File(
        p.join(clone.root, 'packages', 'sibling', 'lib', 'b.dart'),
      ).existsSync(),
      isTrue,
    );
    await clone.apply(mutation);
    expect(
      File(p.join(clone.projectRoot, 'lib', 'a.dart')).readAsStringSync(),
      contains('a - b'),
    );
    await clone.restore(mutation.filePath);

    expect(
      File(p.join(member.path, 'lib', 'a.dart')).readAsStringSync(),
      'int add(int a, int b) => a + b;\n',
    );
    expect(
      File(
        p.join(workspace.path, 'packages', 'sibling', 'lib', 'b.dart'),
      ).readAsStringSync(),
      'const b = 1;\n',
    );
  });

  test('rejects a selected package outside the workspace root', () async {
    final workspace = await fixtureProject();
    final member = await fixtureProject();

    await expectLater(
      Containment.create(
        member.path,
        workspaceRoot: workspace.path,
        paths: await isolatedRadPaths('rad_containment_outside_'),
        ignore: RadIgnore.load(member.path),
      ),
      throwsArgumentError,
    );
  });

  test(
    'applies and restores a mutation without touching the source tree',
    () async {
      const mutation = Mutation(
        filePath: 'lib/a.dart',
        offset: 27,
        length: 1,
        original: '+',
        replacement: '-',
        operatorId: 'arithmetic',
        description: 'replace + with -',
      );
      final copied = File(p.join(containment.root, 'lib/a.dart'));

      await containment.apply(mutation);
      expect(copied.readAsStringSync(), contains('a - b'));
      expect(
        File(p.join(source.path, 'lib/a.dart')).readAsStringSync(),
        contains('a + b'),
      );

      await containment.restore('lib/a.dart');
      expect(copied.readAsStringSync(), contains('a + b'));
    },
  );

  test('rejects a mutation whose original text does not match', () async {
    const drifted = Mutation(
      filePath: 'lib/a.dart',
      offset: 0,
      length: 1,
      original: '+',
      replacement: '-',
      operatorId: 'arithmetic',
      description: 'replace + with -',
    );
    await expectLater(containment.apply(drifted), throwsStateError);
  });

  test('rejects a mutation past the end of the copied file', () async {
    const pastEnd = Mutation(
      filePath: 'lib/a.dart',
      offset: 1000,
      length: 1,
      original: '+',
      replacement: '-',
      operatorId: 'arithmetic',
      description: 'replace + with -',
    );
    await expectLater(containment.apply(pastEnd), throwsStateError);
  });
}
