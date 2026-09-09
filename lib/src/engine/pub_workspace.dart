import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'run_aborted.dart';

/// A selected package and the pub workspace that contains it.
final class PubWorkspace {
  PubWorkspace._({required this.projectRoot, required this.root});

  /// Absolute, normalized root of the package selected for irradiation.
  final String projectRoot;

  /// Absolute, normalized root copied into each containment.
  final String root;

  /// Resolves the workspace reference written by `dart pub get` for
  /// [projectRoot], falling back to a single-package containment.
  static PubWorkspace resolve(String projectRoot) {
    final project = p.normalize(p.absolute(projectRoot));
    final reference = File(
      p.join(project, '.dart_tool', 'pub', 'workspace_ref.json'),
    );
    if (!reference.existsSync()) {
      return PubWorkspace._(projectRoot: project, root: project);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(reference.readAsStringSync());
    } on FormatException {
      throw RunAborted(
        'invalid pub workspace reference ${reference.path}: malformed JSON.',
      );
    }
    final workspaceRoot = decoded is Map<String, dynamic>
        ? decoded['workspaceRoot']
        : null;
    if (workspaceRoot is! String) {
      throw RunAborted(
        'invalid pub workspace reference ${reference.path}: '
        'workspaceRoot is missing or is not a string.',
      );
    }

    final root = p.normalize(
      p.isAbsolute(workspaceRoot)
          ? workspaceRoot
          : p.join(reference.parent.path, workspaceRoot),
    );
    if (!p.equals(root, project) && !p.isWithin(root, project)) {
      throw RunAborted(
        'invalid pub workspace reference ${reference.path}: '
        'workspaceRoot resolves outside the selected package ancestry.',
      );
    }
    if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
      throw RunAborted(
        'invalid pub workspace reference ${reference.path}: '
        'workspaceRoot has no pubspec.yaml.',
      );
    }
    return PubWorkspace._(projectRoot: project, root: root);
  }
}
