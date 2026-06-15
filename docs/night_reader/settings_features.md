# 設定與其他功能

## 職責

擁有多個較小的功能模組：設定頁面群組（閱讀設定、TTS 設定、備份設定、隱私設定、點擊動作設定、其他設定）、關於頁面與更新檢查、歡迎頁與啟動畫面、檔案關聯與深連結處理、全域替換規則管理、快取管理頁面。

## 範圍

### 設定
- `lib/features/settings/settings_page.dart` — 設定主頁（約 11KB）
- `lib/features/settings/settings_provider.dart` — 設定 Provider（約 10KB）
- `lib/features/settings/reading_settings_page.dart` — 閱讀設定（字型、行距、主題等）
- `lib/features/settings/tts_settings_page.dart` — TTS 朗讀設定
- `lib/features/settings/backup_settings_page.dart` — 備份與還原設定
- `lib/features/settings/data_privacy_settings_page.dart` — 資料與隱私設定（約 15KB）
- `lib/features/settings/click_action_config_page.dart` — 點擊動作設定
- `lib/features/settings/other_settings_page.dart` — 其他設定
- `lib/features/settings/provider/` — 設定子 Provider

### 其他功能
- `lib/features/about/` — 關於頁面、版本資訊、更新檢查
- `lib/features/welcome/` — 啟動歡迎頁與 Splash 畫面
- `lib/features/association/` — 檔案關聯（開啟本地檔案）與深連結處理
- `lib/features/replace_rule/` — 全域文字替換規則管理
- `lib/features/cache_manager/` — 快取管理頁面（檢視與清除快取）

## 依賴與影響

- **上游**：基礎設施、資料庫與模型、核心服務（備份、還原、TTS、更新檢查、快取管理等）
- **下游**：閱讀器（閱讀設定影響閱讀器行為）、書架（部分設定影響書架顯示）
- **外部依賴**：shared_preferences（設定持久化）、app_links、receive_sharing_intent、url_launcher、file_picker、share_plus

## 關鍵流程

- **設定變更**：SettingsPage → SettingsProvider → SharedPreferences 寫入 → EventBus 通知相關模組
- **備份**：BackupSettingsPage → BackupService 執行備份 → 檔案匯出
- **還原**：BackupSettingsPage → RestoreService 執行還原 → 資料匯入 → 重新載入
- **深連結**：Association 模組接收外部 intent → 解析檔案路徑/URL → 觸發對應功能
- **更新檢查**：AboutPage → UpdateService 檢查 GitHub Release → 提示更新

## 變更入口與路線

- **新增設定項**：在對應設定頁面加入 UI → 在 `settings_provider.dart` 加入狀態 → 在 `PreferKey` 加入鍵值
- **修改備份流程 UI**：編輯 `backup_settings_page.dart`，與 `backup_service.dart` 協同
- **修改深連結處理**：編輯 `association/` 下的檔案
- **修改替換規則**：編輯 `replace_rule/` 下的檔案
- **修改快取管理 UI**：編輯 `cache_manager/` 下的檔案

## 已知風險

- 設定變更需要透過 EventBus 或 Provider 通知多個模組，通知鏈若中斷會導致設定不生效
- 備份與還原涉及大量檔案操作，容易出現權限或路徑問題
- 深連結處理在不同 Android 版本上行為可能不同
- `data_privacy_settings_page.dart`（~15KB）功能較多，應保持清晰

## 禁止事項

- 不要在設定頁面中直接執行備份/還原邏輯——透過核心服務
- 不要新增設定項而不在 PreferKey 中註冊鍵值
- 不要在設定變更時直接操作其他模組的內部狀態——使用 EventBus
