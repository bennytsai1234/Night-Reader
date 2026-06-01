# 設定與備份

## 目前職責

應用設定（閱讀器外觀、字體、TTS 參數、隱私、其他偏好）、備份匯出（書架+書源+規則打包為 JSON/ZIP）、還原匯入、書架交換（Legado 格式相容）、繁簡轉換。修改設定頁面或備份格式，從這裡開始。

## 範圍

| 路徑 | 職責 |
|---|---|
| `lib/features/settings/` | 設定主頁（SettingsPage）、SettingsProvider（全局設定狀態） |
| `lib/features/settings/provider/` | SettingsProvider（SharedPreferences 讀寫，通知全局）|
| `lib/features/settings/` pages | ReadingSettingsPage（字體、字色、背景、行距）、TtsSettingsPage（語速、音調）、BackupSettingsPage（備份/還原 UI）、PrivacySettingsPage、OtherSettingsPage 等 |
| `lib/core/services/backup_service.dart` | 備份：將 Book + BookSource + ReplaceRule + Bookmark 等打包 |
| `lib/core/services/restore_service.dart` | 還原：從備份檔解壓並寫回 DB |
| `lib/core/services/export_book_service.dart` | 匯出書籍為 TXT |
| `lib/core/services/bookshelf_exchange_service.dart` | 書架交換（Legado 格式書架 JSON 匯入/匯出）|
| `lib/core/services/chinese_utils.dart` | 繁簡轉換（OpenCC 資料）|
| `lib/core/config/app_config.dart` | 靜態設定鏡像（SettingsProvider 的部分設定同步到這裡，供 core 層使用）|
| `lib/core/constant/prefer_key.dart` | SharedPreferences 鍵名常數 |

測試：`test/features/settings/`、`test/core/services/backup_service_test.dart`（含 `test/backup_service_test.dart`）、`test/core/services/chinese_utils_test.dart`、`test/core/services/bookshelf_exchange_service_test.dart`

## 依賴與影響

- **上游**：應用基礎設施（SharedPreferences、AppDatabase）
- **下游**：閱讀器 V2（讀取 SettingsProvider 的字體/主題/TTS 設定）、書架（備份還原後更新書架）、規則引擎（AppConfig.replaceEnableDefault、readerPageAnim）
- **事件**：發出 `upConfig`（設定變更，供 Reader V2 重新載入設定）（見 [event_bus](event_bus.md)）
- **外部**：`assets/opencc/`（繁簡轉換資料）、`file_picker`（選取備份檔）

## 關鍵流程

**設定讀寫流程**：
```
SettingsPage（任一設定頁）→ SettingsProvider
  → SharedPreferences.set*(key, value)
  → notifyListeners()（所有依賴 SettingsProvider 的 widget 重建）
  → AppConfig 靜態欄位更新（供 core 層同步使用）
  → 發 upConfig 事件（供 Reader V2 熱更新設定）
```

**備份流程**：
```
BackupSettingsPage → BackupService.backup()
  → 從 AppDatabase 讀取 Book + BookSource + ReplaceRule + Bookmark + ReadRecord
  → 序列化為 JSON（Legado 格式相容）
  → 打包為 ZIP → 寫入 shareExportDir()
  → 使用者分享或儲存
```

**還原流程**：
```
BackupSettingsPage → RestoreService.restore(file)
  → 解壓 ZIP → 解析各 JSON 檔案
  → DB upsert（不覆蓋，以 URL 為主鍵 merge）
  → 發 upBookshelf 事件 → 書架重新載入
```

## 常見修改入口

- 新增設定項目 → `SettingsProvider`（新增 SharedPreferences key）+ 對應設定頁
- 修改備份格式（新增/移除欄位）→ `backup_service.dart` + `restore_service.dart`（需同步）
- 繁簡轉換 → `chinese_utils.dart`（替換 OpenCC 資料）
- 書架交換格式 → `bookshelf_exchange_service.dart`（Legado JSON 格式相容）

## 修改路線

- 新增設定項：SettingsProvider（持久化）→ 設定頁 UI →（若需要）AppConfig 靜態欄位 → 消費方（Reader V2 等）監聽 upConfig
- 修改備份格式：BackupService 和 RestoreService 必須同步修改；備份版本號控制（如有）需要 migration 邏輯

## Known Risks

- AppConfig 是靜態欄位（非響應式）；只有 Reader V2 通過 upConfig 事件熱更新，其他使用 AppConfig 的地方只在啟動時讀取
- 備份格式與 Legado JSON 相容，但 Legado 格式本身沒有版本鎖定，書源規則欄位可能隨版本變化
- RestoreService 的 merge 策略（以 URL 為主鍵）在書源 URL 變更時可能建立重複書源
- 繁簡轉換的 OpenCC 資料是靜態資產，更新需要重新打包 App

## Reference Notes

None（standalone 模式）

## Do Not Do

- 不要把 WebDAV 同步或雲端備份功能加入這個模組（超出產品範圍）
- 不要讓備份格式破壞 Legado JSON 相容性（使用者可能同時在用 Legado）
- 不要在 SettingsProvider 中做網路請求（只能讀寫 SharedPreferences）
