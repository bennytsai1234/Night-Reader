# 書源管理

## 職責

擁有書源的完整管理介面：書源列表、CRUD 編輯器、除錯工具、書源驗證、分組管理、書源訂閱、以及探索書源功能。

## 範圍

- `lib/features/source_manager/source_manager_page.dart` — 書源管理主頁（約 24KB）
- `lib/features/source_manager/source_manager_provider.dart` — 書源管理 Provider（約 29KB，大量狀態邏輯）
- `lib/features/source_manager/source_editor_page.dart` — 書源編輯器（約 12KB）
- `lib/features/source_manager/source_debug_page.dart` — 書源除錯頁面
- `lib/features/source_manager/source_debug_provider.dart` — 除錯 Provider
- `lib/features/source_manager/source_group_manage_page.dart` — 書源分組管理
- `lib/features/source_manager/source_subscription_page.dart` — 書源訂閱
- `lib/features/source_manager/explore_sources_page.dart` — 探索書源（約 13KB）
- `lib/features/source_manager/views/` — 子視圖元件
- `lib/features/source_manager/widgets/` — 共用元件

## 依賴與影響

- **上游**：基礎設施、資料庫與模型（書源模型）、規則引擎（書源解析）、核心服務（書源檢查／驗證／除錯／切換服務）
- **下游**：搜尋與探索（使用書源進行搜尋）、書架（使用書源取得書籍資訊）
- **外部依賴**：webview_flutter（WebView 書源）、flutter_js

## 關鍵流程

- **新增書源**：SourceEditorPage → 填寫書源規則 JSON → SourceManagerProvider 儲存 → BookSourceService 寫入資料庫
- **驗證書源**：SourceManagerPage 選擇書源 → CheckSourceService → 規則引擎解析 → SourceCheckIsolate 背景執行 → 回報結果
- **除錯書源**：SourceDebugPage → SourceDebugService → 逐步執行規則 → 顯示中間結果
- **書源訂閱**：SourceSubscriptionPage → 從遠端 URL 取得書源列表 → 匯入

## 變更入口與路線

- **修改書源管理 UI**：編輯 `source_manager_page.dart`
- **修改書源狀態管理**：編輯 `source_manager_provider.dart`（極其複雜，約 29KB）
- **修改書源編輯器**：編輯 `source_editor_page.dart`
- **修改書源驗證流程 UI**：與核心服務的 `check_source_service.dart` 協同修改
- **新增書源分組功能**：編輯 `source_group_manage_page.dart`

## 已知風險

- `source_manager_provider.dart`（~29KB）過於龐大，狀態邏輯複雜
- 書源驗證流程涉及 WebView、Cookie、真實網站互動，容易出現僅在特定條件下發生的問題
- 書源規則 JSON 格式與 Legado 相容，修改時需確保格式一致
- 這是 release 的重點回歸區域

## 禁止事項

- 不要在書源管理 UI 中直接執行規則解析——透過核心服務和規則引擎
- 不要在 Provider 中直接操作 UI 元件
- 不要修改書源 JSON 格式而不確保與規則引擎的向後相容性
