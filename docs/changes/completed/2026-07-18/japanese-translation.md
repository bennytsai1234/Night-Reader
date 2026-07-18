# 2026-07-18 日文段落自動翻譯（✅ 已完成）

層級：**T2**（新外部相依 google_mlkit_translation、跨 services / reader chapter 管線 / settings；平台通道功能）。
**Feature freeze 標記**：此為新能力，非既有功能內部改進；使用者 2026-07-18 明確要求（「翻譯書缺譯段落整句日文看不懂，需要內建底層自動轉中文」）。實作落地後記入索引 Architecture Decisions。

## Before（現況）

翻譯書偶有未翻譯的日文段落（整句含假名），閱讀器原樣顯示，使用者無法閱讀。管線現況：raw content（DB 快取）→ `ReaderV2ContentTransformer.process`（worker isolate：替換規則＋重分段＋正規化＋簡繁轉換）→ `ReaderV2ProcessedChapter` → block 排版。無任何翻譯能力。

## After（改完的樣子）

開啟「日文段落自動翻譯」後，含假名的段落在進入排版前被 on-device 機器翻譯成中文（隨使用者簡繁設定輸出），TTS/錨點/進度座標系不受影響；無網路、模型未下載或翻譯失敗時原樣顯示（優雅降級）。

## 設計決策

- **D8 翻譯引擎**：✅建議 **ML Kit on-device translation**（`google_mlkit_translation`）。免費、離線（模型 ja+zh 各約 30MB，首次啟用時下載一次）、Android/iOS 都支援。備選：雲端 API（要金鑰/計費/隱私，違背純工具定位，不採）；只標示不翻（不解決問題，不採）。品質為 NMT 中等水準——「看得懂」優先於「翻得美」，符合需求。
- **D9 顯示模式**：✅建議**譯文取代原文**（版面乾淨、格線一致）。備選「原文下附譯文」增加版面噪音，v1 不做。
- **偵測規則**（純函式，可單測）：逐段判定——平假名（U+3040–309F）＋片假名（U+30A0–30FF，含 ー U+30FC）合計 ≥ 3 字，且假名/(假名+漢字) 比例 ≥ 0.2 才視為日文段。防護：中文網文常見的單字 `の`、擬聲拖長 `啊ー` 不觸發。閾值集中一處常數，便於調。
- **簡繁順序問題（關鍵）**：worker 的簡繁轉換若先把日文漢字轉成繁體（発→發），MT 輸入就不再是日文、品質劣化。因此 **worker 內簡繁轉換對假名偵測命中的行跳過**；翻譯後在主 isolate 對譯文（ML Kit zh 輸出為簡體）套 `ChineseTextConverter`（依使用者設定）＋ `normalizeTypography`（與全章格線一致）。
- **架構位置**：翻譯是平台通道（async、不能進 worker isolate），掛在 `reader_v2_chapter_repository._loadViaV2ContentPipeline` 的 `_contentTransformer.process(...)` 之後：`translator.translateIfNeeded(processed)` 回傳新的 `ReaderV2ProcessedChapter`。逐段處理時剝除 `　　` 縮排前綴、翻譯、再補回。此點在 `ReaderV2Content.fromRaw` 之前，displayText 座標系契約不破，TTS 直接朗讀中文譯文。
- **介面抽象**：`lib/core/services/japanese_translation_service.dart` —— `abstract JapaneseParagraphTranslator`（`Future<String?> translate(String paragraph)`，null＝不可用）＋ `MlkitJapaneseTranslator` 實作＋純函式 `looksJapanese(String line)`。單測用 fake，不碰 ML Kit。
- **模型管理**：設定開關（`PreferKey.readerJapaneseAutoTranslate`，預設關）。開啟時觸發 `OnDeviceTranslatorModelManager` 下載 ja/zh 模型（預設 wifi 條件），設定列 subtitle 顯示下載狀態；模型未就緒時管線直接跳過翻譯。
- **快取**：翻譯結果記憶體 LRU（服務層，key＝日文段落文字 hash，段落粒度——同章重讀/±2 章預載重複命中）。不落地 DB（v1）；真機體感慢再考慮持久化。
- **失敗語意**：任何異常（模型缺、平台錯誤、逾時）→ 回傳原文段落，不擋章節載入、不拋錯進 UI。

## 實作步驟

1. `pubspec.yaml` 加 `google_mlkit_translation`（實作時查最新版；確認 minSdk 相容）。
2. 新增 `japanese_translation_service.dart`（介面＋mlkit 實作＋偵測純函式＋LRU）。
3. worker 簡繁轉換加假名行防護（`reader_v2_content_transformer.dart` 的 `_workerMain` 轉換段與 compute 退回路徑同步改）。
4. `reader_v2_chapter_repository.dart` 注入 translator（走 `reader_v2_dependencies.dart` 既有注入模式），`_loadViaV2ContentPipeline` 加 post-pass。
5. 設定層：`prefer_key.dart`＋`app_config.dart`＋`reader_v2_prefs_repository.dart`＋`reader_v2_settings_controller.dart`＋`reader_v2_settings_sheets.dart` 新增一列（含模型下載狀態 subtitle）。
6. 測試：偵測函式對照表（純日文句/中文句/`XXの店`/`啊ー`/中日混排）；repository post-pass 用 fake translator 驗證縮排保留、簡繁後處理、失敗降級；worker 假名行跳過簡繁的單測。
7. 驗證：`flutter analyze`、`flutter test`；真機一輪（開啟開關→模型下載→開含日文段落的章節→顯示中文＋TTS 唸中文）。

## 風險與備註

- ML Kit zh 模型輸出**簡體**，繁體使用者依賴既有 `ChineseTextConverter` 後處理（管線已內建，成本低）。
- 整章全日文的極端情況：逐段翻譯首次可能數秒，之後 LRU 命中；預載管線本來就是 async，不卡 UI。
- 單機測試環境（WSL）無平台通道：所有單測經 fake；真機驗收走 CI APK。

## 實作結果（2026-07-18）

- 新檔：`core/services/japanese_text_detector.dart`（純函式，worker 可用；閾值調整為核心假名 ≥2 且假名比例 ≥0.15，讓「はい」這類短句也能命中，「XXの店」「啊ーー」仍不觸發）、`core/services/japanese_translation_service.dart`（ML Kit 實作＋模型管理＋段落 LRU 512＋12s 逾時）、`features/reader_v2/chapter/reader_v2_japanese_pass.dart`（transformer 後主 isolate pass）。
- worker 簡繁轉換加假名行防護（`convertChinesePreservingJapanese`，worker 與 compute 退回路徑同步）——此防護**恆開**：即使翻譯關閉，也不再把日文漢字硬轉中文字形（行為變更，屬修正）。
- 設定：進階設定 sheet「日文翻譯」區塊一列 switch（subtitle 綁 `ValueNotifier<JapaneseModelStatus>` 顯示模型狀態），開啟時觸發模型下載（Wi-Fi）；`PreferKey.readerJapaneseAutoTranslate` 預設關；切換 bump `contentSettingsGeneration` 觸發章節重載。
- 相依：`google_mlkit_translation ^0.14.0`（minSdk 24 ✓）。
- 驗證：`flutter analyze` 乾淨；`flutter test` 757 全過（偵測對照表、fake translator pass 測試、worker 假名防護測試）。真機驗收（模型下載→開含日文章節→顯示中文＋TTS 唸中文）待 CI APK。
