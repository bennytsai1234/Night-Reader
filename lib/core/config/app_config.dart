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

  /// Reader V2 B2 末行字距補償；額外排版成本高，預設關閉。
  static bool readerLastLineSpacingCompensation = false;

  /// Reader V2 內文 justify 對照開關（無 UI，em-grid-lock 除錯用）。
  /// 鎖寬後滿列天生切齊右緣，justify 只會把避頭尾列的整格殘差攤進
  /// 字距、破壞直行格線，故預設 false（start 對齊）；真機要對照
  /// 「justify + 鎖寬」觀感時手動改 true。
  static bool readerV2ContentJustify = false;

  /// Reader V2 日文段落自動翻譯（ML Kit on-device）；需下載模型，預設關閉。
  static bool readerJapaneseAutoTranslate = false;
}
