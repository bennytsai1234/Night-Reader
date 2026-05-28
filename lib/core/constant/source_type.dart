class SourceType {
  static const int book = 0;
  static const int audio = 1;
  static const int image = 2;
  static const int file = 3;

  @Deprecated(
    'Reader now follows Legado source type mapping. Use SourceType.file instead.',
  )
  static const int rss = file;
}
