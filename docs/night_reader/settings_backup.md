# 設定與備份

## 現有責任

應用設定（閱讀偏好、TTS 設定、點擊區域設定、其他設定）、備份匯出（書架、書源、設定、閱讀紀錄打包為 zip）、還原匯入、繁簡轉換（OpenCC）設定、書籍匯出。

## 範圍

- **設定 UI**：`lib/features/settings/`（`settings_page.dart`、`settings_provider.dart`、`reading_settings_page.dart`、`tts_settings_page.dart`、`click_action_config_page.dart`、`other_settings_page.dart`、`backup_settings_page.dart`、`data_privacy_settings_page.dart`）
- **備份服務**：`lib/core/services/backup_service.dart`
- **還原服務**：`lib/core/services/restore_service.dart`
- **書籍匯出**：`lib/core/services/export_book_service.dart`
- **繁簡轉換**：`lib/core/services/chinese_utils.dart`（opencc 資料在 `assets/opencc/`）
- **更新忽略清單**：`lib/core/services/update_ignore_store.dart`
- **測試**：`test/features/settings/`、`test/backup_service_test.dart`

## 依賴與下游影響

- 上游：**應用基礎設施**（`shared_preferences` 儲存設定、資料庫所有 DAO 供備份用）
- 下游：**閱讀器 V2**（閱讀設定影響排版參數）、**書架與書籍**（備份包含書架資料）
- 備份格式（zip 結構與 JSON schema）變更需確保向後相容，已有備份的使用者才能正常還原

## 關鍵流程

1. 備份：使用者觸發備份 → `BackupService` 從資料庫讀取全部資料 → 序列化為 JSON → 打包為 zip → 儲存至本地或分享
2. 還原：使用者選擇備份 zip → `RestoreService` 解壓縮 → 驗證格式 → 逐步匯入資料庫
3. 繁簡轉換：`ChineseUtils` 載入 opencc 資料（`assets/opencc/`）→ 在需要時轉換文字

## 變更入口

- 新增設定項目：`settings_provider.dart` + 對應的設定頁面 + `shared_preferences` key（`lib/core/constant/prefer_key.dart`）
- 備份格式擴充：`backup_service.dart`、`restore_service.dart`（需同時維護向後相容）
- TTS 設定：`tts_settings_page.dart`、`settings_provider.dart`

## 變更路由

- 新增備份欄位：`backup_service.dart` 加入序列化 → `restore_service.dart` 加入反序列化（預設值處理舊備份）→ `test/backup_service_test.dart`
- 修改設定 key：`prefer_key.dart` → 確認所有讀取該 key 的地方同步更新（grep `prefer_key`）

## 已知風險

- 備份還原沒有版本號機制；備份格式變更後，舊備份若缺少新欄位可能還原失敗或靜默遺漏資料
- OpenCC 資料放在 `assets/opencc/`，體積較大，修改時需確認 `pubspec.yaml` 資源宣告正確

## 參考備註

無（Standalone 模式）

## 禁止事項

- 不要在備份中包含 Cookie 或認證 token；備份是可分享的，不應包含帳號敏感資料
- 不要直接修改 opencc 二進位資料；若需更新 opencc 版本，需要完整測試繁簡轉換輸出
