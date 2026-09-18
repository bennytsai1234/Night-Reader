import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppStoragePaths', () {
    test(
      'share export files remain direct children of the export directory',
      () async {
        final fileName =
            'safe-export-${DateTime.now().microsecondsSinceEpoch}.json';
        final file = await AppStoragePaths.shareExportFile(fileName);
        addTearDown(() async {
          if (await file.exists()) {
            await file.delete();
          }
        });

        final exportDir = await AppStoragePaths.shareExportDir();

        expect(p.equals(p.dirname(file.path), exportDir.path), isTrue);
      },
    );

    test('rejects export file names containing path traversal', () async {
      await expectLater(
        AppStoragePaths.shareExportFile('../outside.json'),
        throwsArgumentError,
      );
      await expectLater(
        AppStoragePaths.shareExportFile(r'..\outside.json'),
        throwsArgumentError,
      );
    });

    test('rejects book asset keys containing path traversal', () async {
      await expectLater(
        AppStoragePaths.bookAssetDir('../outside', ensureExists: true),
        throwsArgumentError,
      );
    });
  });
}
