import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_file_selection_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('returns null when the picker is cancelled', () async {
    final service = AppFileSelectionService(
      picker:
          ({
            required type,
            required allowedExtensions,
            required allowMultiple,
          }) async => null,
    );

    expect(await service.pickLocalBookPath(), isNull);
  });

  test('accepts an allowed extension case-insensitively', () async {
    const path = '/tmp/NOVEL.TXT';
    final service = AppFileSelectionService(
      picker:
          ({
            required type,
            required allowedExtensions,
            required allowMultiple,
          }) async => _result(path),
    );

    expect(await service.pickLocalBookPath(), path);
  });

  test('rejects a selected path with a disallowed extension', () async {
    final service = AppFileSelectionService(
      picker:
          ({
            required type,
            required allowedExtensions,
            required allowMultiple,
          }) async => _result('/tmp/not-a-book.pdf'),
    );

    expect(await service.pickLocalBookPath(), isNull);
  });

  group('typed picker filters', () {
    final cases = <_PickerCase>[
      _PickerCase(
        name: 'local book',
        expectedExtensions: const ['txt'],
        pick: (service) => service.pickLocalBookPath(),
      ),
      _PickerCase(
        name: 'bookshelf import',
        expectedExtensions: const ['json'],
        pick: (service) => service.pickBookshelfImportPath(),
      ),
      _PickerCase(
        name: 'backup archive',
        expectedExtensions: const ['zip'],
        pick: (service) => service.pickBackupArchivePath(),
      ),
      _PickerCase(
        name: 'book source import',
        expectedExtensions: const ['json', 'txt', 'legado'],
        pick: (service) => service.pickBookSourceImportPath(),
      ),
    ];

    for (final pickerCase in cases) {
      test(
        '${pickerCase.name} passes its complete filter to the picker',
        () async {
          for (final extension in pickerCase.expectedExtensions) {
            late FileType capturedType;
            late List<String> capturedExtensions;
            late bool capturedAllowMultiple;
            final path = '/tmp/import.${extension.toUpperCase()}';
            final service = AppFileSelectionService(
              picker: ({
                required type,
                required allowedExtensions,
                required allowMultiple,
              }) async {
                capturedType = type;
                capturedExtensions = allowedExtensions;
                capturedAllowMultiple = allowMultiple;
                return _result(path);
              },
            );

            expect(await pickerCase.pick(service), path);
            expect(capturedType, FileType.custom);
            expect(capturedAllowMultiple, isFalse);
            expect(capturedExtensions, pickerCase.expectedExtensions);
          }
        },
      );
    }
  });
}

class _PickerCase {
  const _PickerCase({
    required this.name,
    required this.expectedExtensions,
    required this.pick,
  });

  final String name;
  final List<String> expectedExtensions;
  final Future<String?> Function(AppFileSelectionService service) pick;
}

FilePickerResult _result(String path) {
  return FilePickerResult([
    PlatformFile(path: path, name: p.basename(path), size: 0),
  ]);
}
