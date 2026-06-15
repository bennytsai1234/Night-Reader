# 基礎設施

## 職責

擁有 App 的啟動入口、依賴注入設定、全域常數與設定、工具函式、例外處理、共用 UI 資源（主題、導航、共用元件）。所有其他模組都依賴它來取得基礎能力。

## 範圍

- `lib/main.dart` — App 進入點，初始化 DI、Provider、主題、導航
- `lib/app_providers.dart` — 全域 Provider 註冊
- `lib/core/base/` — BaseProvider 基底類別
- `lib/core/config/` — AppConfig 設定
- `lib/core/constant/` — 常數、Pattern、PreferKey、BookType 等
- `lib/core/di/` — get_it 依賴注入設定
- `lib/core/exception/` — AppException 例外類別階層
- `lib/core/utils/` — 通用工具（字串、時間、檔案、編碼、網路、顏色、URL、HTML 等）
- `lib/core/widgets/` — 共用元件（BookCoverWidget）
- `lib/shared/theme/` — 主題定義
- `lib/shared/navigation/` — 導航相關
- `lib/shared/widgets/` — 跨功能共用的 UI 元件

## 依賴與影響

- **上游**：無（最底層）
- **下游**：所有其他模組都依賴基礎設施提供的 DI、主題、工具函式和共用元件
- **外部依賴**：provider、get_it、shared_preferences、logger

## 關鍵流程

- `main()` → `configureDependencies()` → `runApp()` → MaterialApp with theme and routes
- 背景任務 `callbackDispatcher()` 也依賴 DI 初始化
- 例外透過 AppException 階層捕獲，由 CrashHandler 處理

## 變更入口與路線

- **新增全域 Provider**：修改 `app_providers.dart`，必要時在 `di/injection.dart` 註冊
- **新增共用元件**：放入 `lib/shared/widgets/` 或 `lib/core/widgets/`
- **修改主題**：編輯 `lib/shared/theme/`
- **新增路由**：在 `main.dart` 中註冊
- **新增工具函式**：放入 `lib/core/utils/`
- **常數修改**：在 `lib/core/constant/` 中進行，注意 PreferKey 的新增需保持向後相容

## 已知風險

- `main.dart` 隨著功能增加持續膨脹，應定期重構提取
- DI 註冊順序可能影響啟動行為（某些服務需要 eager 初始化）
- `PreferKey` 常數字串若被移除可能導致已儲存的使用者偏好失效

## 禁止事項

- 不要在基礎設施中放置業務邏輯——業務邏輯屬於核心服務或對應的功能模組
- 不要在此模組中直接依賴 features/ 下的程式碼（避免循環依賴）
- 不要將功能特定的 UI 元件放在 shared/widgets/ 中
