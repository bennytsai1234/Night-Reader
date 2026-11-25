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
  Future<List<String>> pickLocalBookPaths() => _pickPaths(_localBook);

  Future<String?> pickBookshelfImportPath() => _pickPath(_bookshelfImport);

  Future<String?> pickBackupArchivePath() => _pickPath(_backupArchive);

  Future<String?> pickBookSourceImportPath() => _pickPath(_bookSourceImport);

  /// 一次選一個檔的匯入。選到的檔還是要照副檔名再驗一次：系統選檔器的
  /// 篩選不是界線。
  Future<String?> _pickPath(_FileSelectionSpec spec) async {
    final paths = await _pickPaths(spec, allowMultiple: false);
    return paths.isEmpty ? null : paths.first;
  }

  Future<List<String>> _pickPaths(
    _FileSelectionSpec spec, {
    bool allowMultiple = true,
  }) async {
    final picker = _picker ?? _pickFiles;
    final result = await picker(
      type: FileType.custom,
      allowedExtensions: List.unmodifiable(spec.allowedExtensions),
      allowMultiple: allowMultiple,
    );
    if (result == null) return const [];
    return [
      for (final file in result.files)
        if (file.path case final path?
            when path.isNotEmpty && _allowed(spec, path))
          path,
    ];
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
