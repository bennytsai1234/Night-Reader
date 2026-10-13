/// 全域應用配置的靜態鏡像
/// 由 SettingsProvider 與 ReaderSettingsMixin 在載入/變更時同步更新
/// 供 Model 層（如 book_extensions.dart）讀取全域預設值
class AppConfig {
  AppConfig._();

  /// 淨化替換規則預設開關（對應 SettingsProvider.replaceEnableDefault）
  static bool replaceEnableDefault = true;

  /// 開 App 時在背景檢查書架更新（對應 SettingsProvider.autoRefresh）
  static bool autoRefresh = true;
}
