# 方案 B 升級交接檔（給任何接手的 coding agent，含 Codex）

你要接手一項進行中的架構升級：把夜讀 Night Reader 的閱讀器核心替換為「方案 B 混合架構」（Framework 滾動骨架 + 自有排版管線）。調查與設計已全部完成並鎖定，你的工作是照既定步驟實作，不需要重新調查或重新設計。

## 開始步驟

1. 讀主計畫檔 `docs/changes/planning/2026-07-09-plan-b-hybrid-reader.md`，按其中「下次 session 續作步驟」繼續執行。
2. 設計真相：`方案B_混合架構開發文檔.md`（repo 根目錄）——六條不變量 I1–I6 與各模組規格，任何實作違反其一一律退回。
3. 整合決策：本目錄 `blueprint.md`——十項決策（D1–D10）、目錄與檔案所有權表、依賴規則。衝突時：整合相容性以 blueprint 為準，引擎內部設計以方案 B 文檔為準。
4. 現況細節：本目錄 7 份 spec（page-assembly / session-runtime / viewport-motion / layout-render-style / chapter-content / features-bridge / tests-baseline），內含必須保留的 API 精確簽名、持久化格式、行為常數。實作每個模組前先讀對應 spec。

## 環境限制（Windows 受控環境）

- Flutter 不在 PATH：一律用完整路徑 `C:\Users\045650\flutter\bin\flutter.bat`。
- 本機無 Android SDK：**不要**嘗試 build APK；驗證只跑 `flutter analyze` 與 `flutter test`（必要時 `dart run build_runner build`）。APK 由 GitHub Actions 建置。
- 不可修改 DB schema、不可新增第三方依賴、不可動 `pubspec.yaml`。
- 每完成一個階段（W1、W2…）就 commit 並 push 到 `main`（使用者政策：完成即提交，不必詢問）。

## 執行方式調整（原計畫為多代理並行所寫）

- 主計畫檔提到「五個代理並行」「agents 一律用 sonnet」是前一工具的多代理編排指令——單線作業的 agent 忽略即可，改為依 blueprint §2 所有權表**逐模組循序實作**（順序：W2-A measure → W2-B text → W2-C paragraph+pump → W2-D view → W2-E anchor/overlay/progress/telemetry），每個模組附單元測試。
- 模組間只透過 `core/hybrid_types.dart` + `core/hybrid_contracts.dart` 互相認識；不得跨模組直接 import 內部實作（依賴規則見 blueprint §3）。

## 目前進度（2026-07-09 Codex）

已完成：

1. W1 契約：新增 `lib/features/reader_v2/hybrid/core/hybrid_types.dart` 與 `hybrid_contracts.dart`，定義 BlockKey、LayoutEpoch、StyleFingerprint、ChapterBlocks、LayoutTask、BlockReady 與各模組抽象介面。
2. W2 基礎模組：
   - `measure/`：DocumentIndex、MeasurementStore、MetricsDiskCache。
   - `text/`：HybridChapterRepository adapter、TextPreprocessor。
   - `paragraph/` + `pump/`：ParagraphCache、LayoutPump、BudgetGovernor、LayoutCostModel。
   - `view/`：HybridScrollView skeleton、RenderCachedBlock、AdmissionController。
   - `anchor/`、`overlay/`、`progress/`、`telemetry/`：AnchorManager、selection/TTS overlay helper、HybridProgress、HybridTelemetry/DebugOverlay。
3. 測試：新增 `test/features/reader_v2/hybrid/` 聚焦測試，覆蓋 core range、DocumentIndex、metrics disk cache、text slicing、ParagraphCache pin、LayoutPump gate、TTS rect 與 progress。

驗證：

- `C:\Users\045650\flutter\bin\flutter.bat test test/features/reader_v2/hybrid`：13 passed。
- `C:\Users\045650\flutter\bin\flutter.bat analyze`：No issues found。
- `C:\Users\045650\flutter\bin\flutter.bat test`：678 passed / 4 skipped。

下一步從 W3 開始：新增 `hybrid_reader_screen.dart`，落實 D5 七個 bridge 閉包與 capture/restore，並改 `reader_v2_page.dart` 切換點與 D6 進度顯示。

## 品質底線

- 每階段結束：`flutter analyze` 零新增問題、`flutter test` 全綠（基線：665 過 / 4 skip）。
- I1–I6 不變量以 debug assert 常駐（落實點見 blueprint §4）。
- W3 整合是全案最高風險段：D5 七個閉包契約、capture/restore、TTS 高亮、進度顯示改制，逐條核對 spec 簽名，不可憑印象。
- 舊碼刪除（W6/D8）只在整合切換完成且全綠之後執行，刪前以全 repo grep 確認無引用。
- 實機幀率驗收（fling p99 ≤ 8.3ms）不在本機範圍，留待 CI APK + device lab。

## 完成後

- 把主計畫檔移到 `docs/changes/completed/{完成日期}/`，並在當日 `summary.md` 附一行。
- 更新 `docs/night_reader/reader.md`（模組邊界已變）與 `docs/night_reader_index.md` 的 Architecture Decisions 表（本升級取代 2026-07 backward lock 決策）。
- 最終 commit + push。
