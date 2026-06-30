# 夜讀 Codebase Atlas

自包含入口與路由器，供本專案日常工作使用。自帶紀律——無需另讀工作流程文件。

## Entry

1. 保留使用者的原始請求。
2. 讀 `docs/night_reader_index.md` 一次，接著用一句白話確認本專案做什麼。
3. 只從索引挑相關模組文件——不要全讀。對該區不熟時先 zoom out 看模組地圖再收斂。
4. 依意圖路由：**know**（解釋、定位、可行性、歸屬、行為檢查、review、重現、profile、CI 失敗、風險）→ Investigate；**change**（任何程式碼編輯）→ Change；混合/不明 → 先 investigate 再決定。
5. 結論往下傳；除非需要尚未收集的脈絡，否則不跨步驟重讀索引或模組文件。

## Investigate (read-only)

從 atlas 加最少必要程式碼回答；區分確認事實與假設/未知。絕不編輯——若需修正，在使用者同意後交給 Change。依問題性質套紀律：除錯=重現→排序假設→二分；review=對著 owning/boundary 模組讀 diff；開放設計問題=一次一題訪談、各附推薦答案，比對索引與 Architecture Decisions 表——標記任何與已記責任/邊界衝突或重開已錄決策的提案。

注意本專案特性：閱讀器 Reader V2 與 Source Manager 為重點回歸區；書源驗證涉 WebView/Cookie，易只真機復現，優先用 `tool/` 腳本重現；後台 Isolate 不可執行 JS 規則。

## Change (any edit)

判斷紀律層級並調整 effort：

- **T0 trivial**（無邏輯變、可逆、單檔）：一行 Before/After；略過 plan 檔；跑單一最相關 check。
- **T1 normal**（可控、可逆、診斷清楚）：有便宜縫隙時加一個聚焦測試；編輯 source 前寫草稿 plan `docs/changes/planning/{{DATE}}-{{SLUG}}.md`（`{{DATE}}` = 今日本地日期，ISO `YYYY-MM-DD`）。
- **T2 hard/risky**（async/stateful bug、跨模組、外部 API、不可逆、效能迴歸、診斷不明）：完整紀律；同一 plan 檔；通常需 Decision Gate。

**硬底線：** 不可逆、跨模組、外部 API、遷移工作至少 T2。可接受「快一點/仔細一點」的白話覆寫，但永不低於底線。

**Before / After gate**（唯一確認介面）：
- **Before**：現況與為何需要改——bug 的已診斷根因——用白話。
- **After**：改完會變成什麼、將如何驗證。

T1/T2 編輯任何檔案前等待明確確認。T0（無邏輯變、可逆、單檔）說一行 Before/After 後不等待直接做，做完回報——若 Before 有誤可逆還原。

**Decision Gate** —— 變更會改模組邊界、外部 API、不可逆或遷移，或有兩個以上可行方案時：先查提案是否與索引或 Architecture Decisions 表中已錄者衝突或重開——若是，點名並確認正在重開舊決策。然後給 Context / Options（A/B 含取捨）/ Recommendation，在 Before/After 前等待選擇。跨模組決策錄入索引的 Architecture Decisions 表；模組層錄入該模組 Known Risks。

編輯後依層級驗證；驗證結果一律入報告——不在失敗的 check 上宣稱完成。完成後把 plan 移到 `docs/changes/completed/{{DATE}}/{{SLUG}}.md`，並在當日 `docs/changes/completed/{{DATE}}/summary.md`（當日工作摘要）附一行。僅當模組邊界、歸屬或外部 API 變動才更新 atlas 文件——增量更新，不重掃。

驗證指令：`flutter analyze`、`flutter test`；書源相關變更用 `tool/` 驗證腳本。schema 變更需 `dart run build_runner build`。本機不做 build；APK 建置與發布一律在 GitHub Actions。

## Reporting & delivery

- 回報層級：technical — 使用者回報含模組名、路徑、相關程式碼脈絡。
- 交付政策：no commit — 只寫檔，使用者自行審查後提交。
- 除非使用者明確要求全重建，否則不重跑 Codebase Atlas 初始化。