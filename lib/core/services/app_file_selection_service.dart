import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

typedef AppPickFiles =
    Future<FilePickerResult?> Function({
      required FileType type,
      required List<String> allowedExtensions,
      required bool allowMultiple,
    });

/// App-owned facade for selecting import files.
///
/// Native pickers are filters rather than a trust boundary. Every selected
/// path is therefore validated again before it can reach an import service.
class AppFileSelectionService {
  const AppFileSelectionService({AppPickFiles? picker}) : _picker = picker;

  static const AppFileSelectionService instance = AppFileSelectionService();

  final AppPickFiles? _picker;

  static const _localBook = _FileSelectionSpec(allowedExtensions: ['txt']);

  static const _bookshelfImport = _FileSelectionSpec(
    allowedExtensions: ['json'],
  );

  static const _backupArchive = _FileSelectionSpec(allowedExtensions: ['zip']);

  static const _bookSourceImport = _FileSelectionSpec(
    allowedExtensions: ['json', 'txt', 'legado'],
  );

  Future<String?> pickLocalBookPath() => _pickPath(_localBook);

  Future<String?> pickBookshelfImportPath() => _pickPath(_bookshelfImport);

  Future<String?> pickBackupArchivePath() => _pickPath(_backupArchive);

  Future<String?> pickBookSourceImportPath() => _pickPath(_bookSourceImport);

  Future<String?> _pickPath(_FileSelectionSpec spec) async {
    final picker = _picker ?? _pickFiles;
    final result = await picker(
      type: FileType.custom,
      allowedExtensions: List.unmodifiable(spec.allowedExtensions),
      allowMultiple: false,
    );
    if (result == null || !result.isSinglePick) return null;

    final path = result.files.single.path;
    if (path == null || path.isEmpty) return null;

    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!spec.allowedExtensions.contains(extension)) return null;

    return path;
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
