import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Default library source of the fixture package.
const fixtureCalc = 'int add(int a, int b) => a + b;\n';

/// Library source whose second function no fixture test reaches.
const fixturePartiallyTestedCalc = '''
int add(int a, int b) => a + b;
bool isEven(int n) => n % 2 == 0;
''';

/// Default suite of the fixture package: kills the `+ → -` mutant.
const fixtureTest = '''
import 'package:fixture/calc.dart';
import 'package:test/test.dart';

void main() {
  test('adds', () => expect(add(2, 3), 5));
}
''';

/// Creates a resolvable single-package fixture with one lib and one suite.
///
/// [resolve] runs `dart pub get` in it; skip it to test provisioning.
Future<Directory> createFixturePackage({
  String calc = fixtureCalc,
  String testSource = fixtureTest,
  bool resolve = true,
}) async {
  final dir = await Directory.systemTemp.createTemp('rad_fixture_');
  addTearDown(() => dir.delete(recursive: true));
  void write(String relative, String content) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: fixture
environment:
  sdk: ^3.0.0
dev_dependencies:
  test: any
''');
  write('lib/calc.dart', calc);
  write('test/calc_test.dart', testSource);

  if (!resolve) return dir;
  final pubGet = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'get',
  ], workingDirectory: dir.path);
  if (pubGet.exitCode != 0) {
    fail('fixture pub get failed: ${pubGet.stdout}${pubGet.stderr}');
  }
  return dir;
}

/// Creates an unresolved pub workspace whose selected member imports a
/// version-constrained, unpublished sibling package.
Future<({Directory root, Directory member, Directory sibling})>
createFixtureWorkspace() async {
  final root = await Directory.systemTemp.createTemp('rad_fixture_workspace_');
  addTearDown(() => root.delete(recursive: true));
  final member = Directory(p.join(root.path, 'packages', 'member'));
  final sibling = Directory(p.join(root.path, 'packages', 'sibling'));
  void write(String relative, String content) {
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: rad_fixture_workspace
publish_to: none
environment:
  sdk: ^3.13.0
workspace:
  - packages/member
  - packages/sibling
''');
  write('packages/member/pubspec.yaml', '''
name: fixture
version: 1.0.0
resolution: workspace
environment:
  sdk: ^3.13.0
dependencies:
  rad_fixture_sibling: ^1.0.0
dev_dependencies:
  test: any
''');
  write('packages/member/lib/calc.dart', '''
import 'package:rad_fixture_sibling/value.dart';

int calculate() => siblingValue + 1;
''');
  write('packages/member/test/calc_test.dart', '''
import 'package:fixture/calc.dart';
import 'package:test/test.dart';

void main() {
  test('uses the workspace sibling', () => expect(calculate(), 3));
}
''');
  write('packages/sibling/pubspec.yaml', '''
name: rad_fixture_sibling
version: 1.0.0
resolution: workspace
environment:
  sdk: ^3.13.0
''');
  write('packages/sibling/lib/value.dart', 'const siblingValue = 2;\n');

  return (root: root, member: member, sibling: sibling);
}
