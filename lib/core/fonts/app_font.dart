/// 正文與 App 介面可選的字型（ADR 0045）。
///
/// [system] 是手機自己的字型（原本的樣子）；其他的選了才下載，檔案固定在
/// 某一版，下載後照 [AppFontFile.sha256] 核對，對不上就不用。只下載標準粗細，
/// 要粗的地方由排版引擎合成。
enum AppFont {
  system('system', '系統字型', null),
  notoSerifTc(
    'notoSerifTc',
    '思源宋體',
    AppFontFile(
      family: 'NightReaderNotoSerifTC',
      fileName: 'NotoSerifTC-Regular.otf',
      // Noto Serif CJK 2.003 的繁中子集（SubsetOTF/TC），比完整版小三分之二；
      // 子集外的罕見字由系統字型補上。
      url:
          'https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/'
          'Serif/SubsetOTF/TC/NotoSerifTC-Regular.otf',
      bytes: 7936104,
      sha256:
          '63515eb0622d589a2f4062e8757c598b3da3bffd053f69abd181c210158ef10c',
    ),
  ),
  wenkaiTc(
    'wenkaiTc',
    '霞鶩文楷',
    AppFontFile(
      family: 'NightReaderWenKaiTC',
      fileName: 'LXGWWenKaiTC-Regular.ttf',
      url:
          'https://raw.githubusercontent.com/lxgw/LxgwWenkaiTC/v1.530/'
          'fonts/TTF/LXGWWenKaiTC-Regular.ttf',
      bytes: 15341148,
      sha256:
          '6662480a3f95b4a90c80b189c679617a48adce3a505118a6af63ce5a482b83fa',
    ),
  );

  const AppFont(this.id, this.label, this.file);

  /// 存進偏好設定的值，不得更改。
  final String id;
  final String label;

  /// 要下載的檔案；[system] 是 null。
  final AppFontFile? file;

  static AppFont fromStorage(String? id) {
    for (final font in values) {
      if (font.id == id) return font;
    }
    return system;
  }
}

/// 一套要下載的字型檔。
final class AppFontFile {
  const AppFontFile({
    required this.family,
    required this.fileName,
    required this.url,
    required this.bytes,
    required this.sha256,
  });

  /// 註冊給排版引擎的字族名稱。
  final String family;
  final String fileName;
  final String url;

  /// 檔案大小（位元組），下載時顯示進度、也先用它粗略核對。
  final int bytes;
  final String sha256;

  /// 給人看的大小，例如「15 MB」。
  String get sizeLabel => '${(bytes / 1000000).round()} MB';
}
