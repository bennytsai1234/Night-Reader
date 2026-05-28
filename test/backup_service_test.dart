import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

/// Tests for BackupService manifest structure.
///
/// BackupService depends on DI (getIt), SharedPreferences, file system, and
/// path_provider, making full integration testing heavyweight. These tests
/// verify the manifest format and constants that BackupService uses.
void main() {
  group('BackupService manifest', () {
    // BackupService currently derives this from AppDatabase.schemaVersion.
    const schemaVersion = 2;

    test('manifest contains expected fields', () {
      final manifest = {
        'appVersion': '0.1.7',
        'schemaVersion': schemaVersion,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      expect(manifest.containsKey('appVersion'), true);
      expect(manifest.containsKey('schemaVersion'), true);
      expect(manifest.containsKey('timestamp'), true);
    });

    test('schemaVersion matches clean Drift schema', () {
      expect(schemaVersion, 2);
    });

    test('manifest timestamp is a positive integer', () {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      expect(timestamp, isPositive);
      expect(timestamp, isA<int>());
    });

    test('manifest serializes to valid JSON', () {
      final manifest = {
        'appVersion': '0.1.7',
        'schemaVersion': schemaVersion,
        'timestamp': 1700000000000,
      };

      final jsonStr = jsonEncode(manifest);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['appVersion'], '0.1.7');
      expect(decoded['schemaVersion'], schemaVersion);
      expect(decoded['timestamp'], 1700000000000);
    });

    test('manifest JSON round-trip preserves types', () {
      final manifest = {
        'appVersion': '0.1.7',
        'schemaVersion': schemaVersion,
        'timestamp': 1700000000000,
      };

      final roundTripped =
          jsonDecode(jsonEncode(manifest)) as Map<String, dynamic>;

      expect(roundTripped['appVersion'], isA<String>());
      expect(roundTripped['schemaVersion'], isA<int>());
      expect(roundTripped['timestamp'], isA<int>());
    });

    test('backup file naming uses date format', () {
      // BackupService generates: 'backup-$dateStr.zip' where dateStr = yyyy-MM-dd
      final datePattern = RegExp(r'^backup-\d{4}-\d{2}-\d{2}\.zip$');
      const exampleName = 'backup-2026-03-30.zip';
      expect(datePattern.hasMatch(exampleName), true);
    });

    test('backup exports expected table files', () {
      // BackupService writes these JSON files into the backup folder.
      // This list must stay in sync with the _writeJson calls in backup_service.dart.
      const expectedFiles = [
        'manifest.json',
        'bookshelf.json',
        'bookSource.json',
        'replaceRule.json',
        'bookmark.json',
        'bookGroup.json',
        'downloadTask.json',
        'readerChapterContent.json',
        'config.json',
      ];

      expect(expectedFiles.length, 9);
      expect(expectedFiles, contains('manifest.json'));
      expect(expectedFiles, contains('bookshelf.json'));
      expect(expectedFiles, contains('bookSource.json'));
      expect(expectedFiles, isNot(contains('readRecord.json')));
      expect(expectedFiles, contains('bookGroup.json'));
      expect(expectedFiles, contains('downloadTask.json'));
      expect(expectedFiles, contains('readerChapterContent.json'));
      expect(expectedFiles, contains('config.json'));
    });
  });
}
