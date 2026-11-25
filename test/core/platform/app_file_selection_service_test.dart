import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/platform/app_file_selection_service.dart';

void main() {
  test('本地書一次可以選好幾個檔，只留認得的副檔名', () async {
    var multiple = false;
    final service = AppFileSelectionService(
      picker:
          ({
            required FileType type,
            required List<String> allowedExtensions,
            required bool allowMultiple,
          }) async {
            multiple = allowMultiple;
            return FilePickerResult([
              PlatformFile(path: r'C:\書\甲.txt', name: '甲.txt', size: 1),
              PlatformFile(path: r'C:\書\乙.epub', name: '乙.epub', size: 1),
              PlatformFile(path: r'C:\書\圖.jpg', name: '圖.jpg', size: 1),
              PlatformFile(name: '雲端.txt', size: 1),
            ]);
          },
    );

    expect(await service.pickLocalBookPaths(), [r'C:\書\甲.txt', r'C:\書\乙.epub']);
    expect(multiple, isTrue, reason: '選檔器要打開多選');
  });

  test('取消選檔時是空的清單', () async {
    final service = AppFileSelectionService(
      picker: ({
        required FileType type,
        required List<String> allowedExtensions,
        required bool allowMultiple,
      }) async => null,
    );

    expect(await service.pickLocalBookPaths(), isEmpty);
  });
}
