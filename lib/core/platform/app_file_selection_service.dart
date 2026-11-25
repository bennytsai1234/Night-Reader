import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

typedef AppPickFiles = Future<FilePickerResult?> Function({
  required FileType type,
  required List<String> allowedExtensions,
  required bool allowMultiple,
});

/// App-owned facade for selecting import files.
///
/// Native pickers are filters rather than a trust boundary. Every selected
/// path is therefore validated again before it can reach an import service.
class AppFileSelectionService {
  const AppFileSelectionService({this._picker});

  static const AppFileSelectionService instance = AppFileSelectionService();

  final AppPickFiles? _picker;

  /// 本地書：TXT、EPUB，以及單一個 CBZ／ZIP 的本地漫畫（ADR 0052）。
  static const _localBook = _FileSelectionSpec(
    allowedExtensions: ['txt', 'epub', 'cbz', 'zip'],
  );

  static const _bookshelfImport = _FileSelectionSpec(
    allowedExtensions: ['json'],
  );

  static const _backupArchive = _FileSelectionSpec(allowedExtensions: ['zip']);

  static const _bookSourceImport = _FileSelectionSpec(
    allowedExtensions: ['json', 'txt', 'legado'],
  );

  /// 書架加入本地書：可以一次選好幾個檔（L1），取消時是空的清單。
  /// 系統選檔器不一定照副檔名篩選，被篩掉的檔名也一起交回，算進匯入失敗。
  Future<({List<String> paths, List<String> rejected})>
  pickLocalBookPaths() async {
    final picker = _picker ?? _pickFiles;
    final result = await picker(
      type: FileType.custom,
      allowedExtensions: List.unmodifiable(_localBook.allowedExtensions),
      allowMultiple: true,
    );
    if (result == null) {
      return (paths: const <String>[], rejected: const <String>[]);
    }
    final paths = <String>[];
    final rejected = <String>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null || path.isEmpty || !_allowed(_localBook, path)) {
        rejected.add(p.basenameWithoutExtension(file.name));
        continue;
      }
      paths.add(path);
    }
    return (paths: paths, rejected: rejected);
  }

  Future<String?> pickBookshelfImportPath() => _pickPath(_bookshelfImport);

  Future<String?> pickBackupArchivePath() => _pickPath(_backupArchive);

  Future<String?> pickBookSourceImportPath() => _pickPath(_bookSourceImport);

  /// 一次選一個檔的匯入。選到的檔還是要照副檔名再驗一次：系統選檔器的
  /// 篩選不是界線。
  Future<String?> _pickPath(_FileSelectionSpec spec) async {
    final picker = _picker ?? _pickFiles;
    final result = await picker(
      type: FileType.custom,
      allowedExtensions: List.unmodifiable(spec.allowedExtensions),
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.first.path;
    if (path == null || path.isEmpty || !_allowed(spec, path)) return null;
    return path;
  }

  static bool _allowed(_FileSelectionSpec spec, String path) {
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    return spec.allowedExtensions.contains(extension);
  }

  static Future<FilePickerResult?> _pickFiles({
    required FileType type,
    required List<String> allowedExtensions,
    required bool allowMultiple,
  }) {
    return FilePicker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    );
  }
}

class _FileSelectionSpec {
  const _FileSelectionSpec({required this.allowedExtensions});

  final List<String> allowedExtensions;
}
