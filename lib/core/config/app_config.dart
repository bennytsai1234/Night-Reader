/// 全域應用配置的靜態鏡像
/// 由 SettingsProvider 與 ReaderSettingsMixin 在載入/變更時同步更新
/// 供 Model 層（如 book_extensions.dart）讀取全域預設值
class AppConfig {
  AppConfig._();

  /// 淨化替換規則預設開關（對應 SettingsProvider.replaceEnableDefault）
  static bool replaceEnableDefault = true;

  /// 閱讀器翻頁動畫預設（對應 ReaderSettingsMixin.pageTurnMode）
  /// 0 = 滑動, 1 = 滾動
  static int readerPageAnim = 0;

  /// Reader V2 文字排版正規化的全域鏡像。
  static bool readerTypographyNormalizePunctuation = true;
  static bool readerTypographyPairQuotes = false;
  static bool readerTypographyCollapsePunctuation = false;
  static bool readerTypographyRemoveCjkSpaces = false;

  /// Reader V2 B2 末行字距補償；額外排版成本高，預設關閉。
  static bool readerLastLineSpacingCompensation = false;
}
