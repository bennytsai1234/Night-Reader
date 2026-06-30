# settings_about

## Responsibility

- 設定頁群（主題/閱讀/TTS/備份/隱私/其他/點擊區）與關於/版本更新檢查、崩潰日誌頁。
- 未來工作從這裡開始：設定儲存、主題套用、版本更新檢查、崩潰日誌檢視。

## Scope

- `lib/features/settings/settings_page.dart`、`settings_provider.dart`（251 行，`SettingsProvider extends SettingsProviderBase`，主題色/封面/狀態列/隱私/備份，同步 `AppConfig`）、`provider/settings_base.dart`。
- 子頁：`reading_settings_page.dart`、`tts_settings_page.dart`、`backup_settings_page.dart`、`data_privacy_settings_page.dart`、`other_settings_page.dart`、`click_action_config_page.dart`。
- `lib/features/about/about_page.dart`、`update_check_runner.dart`、`update_dialog.dart`、`crash_log_page.dart`。

## Dependencies & Impact

- 上游：`config/app_config`、`constant/prefer_key`、`services/{tts,backup_service,restore_service,update_service,app_log_service,crash_handler}`、`di`、`shared/theme`。
- 下游影響：`SettingsProvider`↔`AppConfig` 雙向同步，影響 reader/models；備份還原影響全資料；點擊區設定影響 reader `ReaderV2TapAction`；主題影響全 App。
- 更新檢查：`UpdateCheckRunner` + `services/update_service.dart`（GitHub releases）。

## Key Flows

- 設定變更 → `SettingsProvider` → `SharedPreferences` + `AppConfig` 鏡像 → `AppEventBus.upConfig` → 各 feature 套用。
- 備份：`backup_settings_page` → `BackupService` zip 匯出；還原 → `RestoreService`。
- 更新：`about_page` → `UpdateCheckRunner` → `update_service` → `update_dialog`。

## Change Entry Points & Routes

- 設定值/持久化：`settings_provider.dart` + `constant/prefer_key.dart` + `config/app_config.dart`（三方需一致）。
- 主題：`shared/theme/*` + `settings_provider.dart`。
- 備份還原：`backup_settings_page.dart` + `services/{backup_service,restore_service}.dart`。
- 更新檢查：`about/update_check_runner.dart` + `services/update_service.dart`。
- 崩潰日誌：`about/crash_log_page.dart` + `services/{app_log_service,crash_handler}.dart`。
- 點擊區：`click_action_config_page.dart` + reader `features/menu/reader_v2_tap_action.dart`。

## Known Risks

- `SettingsProvider`↔`AppConfig`↔`PreferKey` 三方不同步會使 reader 讀到舊值（見 foundation 模組）。
- 備份還原 schema 變更會破壞舊備份（見 services）。
- 更新檢查依賴 GitHub releases API，網路/格式變動會失敗。

## Do Not Do

- 不要把閱讀設定另存於 reader 內（統一走 `PreferKey`+`AppConfig`）。
- 不要在 settings 直接操作書源/下載（層 source_manager/downloads）。