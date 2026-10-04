import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the release wiring.
///
/// A release workflow is the one thing in this repository whose failure is
/// invisible until a user installs the artifact. These tests check the
/// properties that make it safe: strict version parsing, no publishing, and the
/// permission gate being a real script anyone can run rather than a CI step
/// buried in a workflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String read(String path) => File(path).readAsStringSync();

  group('release workflow', () {
    late String yaml;

    setUp(() => yaml = read('.github/workflows/release.yml'));

    test('exists and triggers on version tags', () {
      expect(yaml, contains("tags: ['v*']"));
      expect(yaml, contains('workflow_dispatch'));
    });

    test('never publishes', () {
      expect(
        yaml,
        contains('draft: true'),
        reason: 'a published release cannot be replaced once users install it',
      );
      expect(
        yaml,
        isNot(contains('draft: false')),
        reason: 'there must be no path that publishes',
      );
    });

    test('rejects a tag that is not MAJOR.MINOR.PATCH', () {
      expect(
        yaml,
        contains(r"'^[0-9]+\.[0-9]+\.[0-9]+$'"),
        reason: 'a tag like v1.2 must fail loudly, not become 1.2.0',
      );
      expect(yaml, contains('does not parse as vMAJOR.MINOR.PATCH'));
    });

    test('derives the version from the tag rather than hardcoding it', () {
      expect(yaml, contains(r'VERSION="${TAG#v}"'));
      expect(
        yaml,
        isNot(contains('version: 1.0.0+1')),
        reason: 'the version must come from the tag',
      );
    });

    test('verifies the built APK rather than trusting the build', () {
      expect(yaml, contains('verify-apk-permissions.sh'));
      expect(yaml, contains('dump badging'));
      expect(
        yaml,
        contains('versionName'),
        reason: 'the APK must be checked against the tag',
      );
    });

    test('checks the Windows zip is runnable, not just built', () {
      expect(yaml, contains('pixelforge.exe'));
      expect(
        yaml,
        contains('no DLLs'),
        reason: 'a zip without the plugin DLLs will not start',
      );
    });

    test('builds every required artifact', () {
      for (final command in [
        'flutter build apk --release',
        'flutter build apk --release --split-per-abi',
        'flutter build appbundle --release',
        'flutter build windows --release',
      ]) {
        expect(yaml, contains(command), reason: 'missing: $command');
      }
    });

    test('names artifacts with the version', () {
      expect(yaml, contains(r'pixelforge-${VERSION}-universal.apk'));
      expect(yaml, contains(r'pixelforge-${VERSION}.aab'));
    });

    test('uses the release keystore and never silently debug-signs', () {
      expect(yaml, contains('RELEASE_KEYSTORE_B64'));
      expect(yaml, contains('KEYSTORE_PASSWORD'));
      expect(yaml, contains('KEY_ALIAS'));
      expect(yaml, contains('KEY_PASSWORD'));
      expect(
        yaml,
        contains('must not be published'),
        reason: 'the throwaway-key path must warn that it is not shippable',
      );
    });

    test(
      'fails when an artifact is missing rather than publishing nothing',
      () {
        expect(yaml, contains('if-no-files-found: error'));
        expect(yaml, contains('fail_on_unmatched_files: true'));
      },
    );

    test('carries a checklist for the human who promotes the draft', () {
      expect(yaml, contains('Verify before promoting'));
      expect(yaml, contains('versionName'));
    });
  });

  group('permission verification script', () {
    late String script;

    setUp(() => script = read('scripts/verify-apk-permissions.sh'));

    test('is runnable by hand and takes an APK argument', () {
      expect(script, contains('usage:'));
      expect(script, contains(r'$0 <path-to.apk>'));
    });

    test('distinguishes "no permissions" from "could not check"', () {
      expect(
        script,
        contains('exit 2'),
        reason: 'a missing aapt2 must not read as a pass',
      );
    });

    test('fails on any permission, not only INTERNET', () {
      expect(
        script,
        contains('FAIL: the APK declares permissions'),
        reason: 'the product ships zero permissions, not "no INTERNET"',
      );
      expect(script, contains('exit 1'));
    });

    test('mentions INTERNET explicitly for the reader', () {
      expect(script, contains('android.permission.INTERNET'));
    });

    test('picks the newest aapt2 by version, not alphabetically', () {
      expect(
        script,
        contains('sort -V'),
        reason: 'lexicographic sort puts 10.0 before 9.0',
      );
    });

    test('checks the artifact, not the source manifest', () {
      expect(script, contains('source and artifact can disagree'));
    });
  });

  group('publishing documentation', () {
    late String docs;

    setUp(() => docs = read('docs/RELEASING.md'));

    test('says a draft must not be published automatically', () {
      expect(docs.toLowerCase(), contains('nothing is ever published'));
    });

    test('documents the version proposal rather than applying it silently', () {
      expect(docs, contains('Proposed'));
      expect(
        docs,
        contains('1.0.0+24'),
        reason: 'the phase requires a proposal recorded in the docs',
      );
    });

    test('documents the exit codes of the verification script', () {
      expect(docs, contains('| 0 |'));
      expect(docs, contains('| 1 |'));
      expect(docs, contains('| 2 |'));
    });

    test('warns that a throwaway-key build must not be published', () {
      expect(
        docs,
        contains('must not be published'),
        reason: 'a throwaway-signed APK cannot be updated later',
      );
    });

    test('notes iOS as future work rather than pretending it builds', () {
      expect(docs, contains('Not built'));
      expect(docs, contains('future work'));
    });
  });

  group('version state', () {
    test('the declared version still needs a human decision', () {
      final line = read(
        'pubspec.yaml',
      ).split('\n').firstWhere((l) => l.startsWith('version:'));
      expect(
        line,
        startsWith('version: 1.0.0+'),
        reason:
            'if the version is bumped, update this expectation and '
            'docs/RELEASING.md together',
      );
    });

    test('the release workflow reads the version from the tag', () {
      // If pubspec and the tag ever disagreed, the stamped build would be
      // labelled by the tag. That is the documented behaviour, so it is
      // asserted rather than assumed.
      final yaml = read('.github/workflows/release.yml');
      expect(yaml, contains(r'VERSION="${TAG#v}"'));
      expect(yaml, contains('Stamp the version from the tag'));
    });
  });
}
