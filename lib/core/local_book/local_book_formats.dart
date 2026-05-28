const Set<String> kSupportedLocalBookExtensions = {'txt', 'epub', 'umd'};

bool isSupportedLocalBookExtension(String ext) {
  final normalized = ext.startsWith('.') ? ext.substring(1) : ext;
  return kSupportedLocalBookExtensions.contains(normalized.toLowerCase());
}
