import 'package:path/path.dart' as p;

const Set<String> kSupportedLocalBookExtensions = {'txt'};

bool isSupportedLocalBookExtension(String ext) {
  final normalized = ext.startsWith('.') ? ext.substring(1) : ext;
  return kSupportedLocalBookExtensions.contains(normalized.toLowerCase());
}

String localBookExtensionFromPath(String path) {
  final filePath =
      path.startsWith('local://') ? path.substring('local://'.length) : path;
  return p.extension(filePath).replaceFirst('.', '').toLowerCase();
}

bool isSupportedLocalBookPath(String path) {
  final extension = localBookExtensionFromPath(path);
  return extension.isNotEmpty && isSupportedLocalBookExtension(extension);
}
