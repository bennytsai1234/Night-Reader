# 07 — 跨模組關聯影響

> 範圍：Reader V2 變更時需連帶檢查的跨模組關聯（atlas 明確列出「書源、閱讀器、下載、快取與備份彼此有關聯」）。共 6 條。

## X1【中】換源流程直接操作 DAO + Storage，舊 runtime 未 await 的儲存可能與新源競爭寫入

- **位置**：`shell/reader_v2_page.dart:289-344`
- **Tier**：T2（跨模組：閱讀器 + 書源管理 + 資料庫）
- **問題**：換源流程直接操作 `bookDao` + `chapterDao` + `bookStorageService`，`pushReplacement` 後舊 runtime 未 await 的 `_saveVisibleAnchorAfterViewportSettled` 可能與新源位置競爭寫入 DB，造成新源開啟後仍被舊源進度覆寫。
- **改善方向**：換源流程在 `pushReplacement` 前 `await` 取消舊 runtime 所有 pending save；或掛 generation / dispose gate；換源前最終一次 capture 並存為舊源位置，再切換。
- **關聯影響**：書源管理（`source_switch_service`）、書架（`bookDao`）、核心服務（`book_storage_service`）。
- **驗證**：換源後舊 runtime 不再寫 DB；翻幾頁後立刻換源，新源開啟位置等於「換源當下 ChapterIndex」對齊後位置，不被舊位置覆寫。

## X2【中】ProgressController 改共享 Book，與書架／詳情／備份共用 reference

- **位置**：`runtime/reader_v2_progress_controller.dart:62-79`
- **Tier**：T2（跨模組：書架、詳情、備份還原）
- **問題**：`ProgressController._write` 直接修改 `Book` 共享 reference，與書架、詳情頁、備份還原共用，mutation 會同步反映到書架 UI 半更新狀態。
- **改善方向**：與子報告 01 A1 一併處理。`Book` mutation 收到 `BookDao`／事件匯流排；閱讀器傳 location，由服務層統一持久化。
- **關聯影響**：書架（書架 UI 即時監聽 Book）、詳情頁、備份還原序列化 Book 的一致性。
- **驗證**：書架在閱讀時不會半更新；備份還原後 Book 進度欄位一致。

## X3【中】ChapterRepository.ensureChapters 發網路抓章節寫 DB，與下載／預載入服務爭用書源

- **位置**：`content/reader_v2_chapter_repository.dart:79-101`
- **Tier**：T2（跨模組：核心服務下載／預載入／網路層）
- **問題**：與子報告 01 A2 同一位置。在閱讀器模組內發網路、寫 DB，與下載／預載入服務爭用書源、cookie、速率限制，可能重複請求同一 API、違反速率上限。
- **改善方向**：抽 `ReaderChapterSyncService`（核心服務）封裝目錄抓取與寫入，由下載／預載入／閱讀器共用同一入口，避免並發重複請求。
- **關聯影響**：下載、預載入、網路層（cookie、速率限制）。
- **驗證**：閱讀器同時下載章節時不會對同一書源發重複請求；速率限制由網路層統一把關。

## X4【低】SessionFacade.addCurrentBookToBookshelf 與書架 addBook 平行實作

- **位置**：`application/session/reader_v2_session_facade.dart:11-39`
- **Tier**：T1（跨模組：書架 add book）
- **問題**：與書架 add book 平行實作，需確保 `totalChapterNum` / `durChapterTime` / `syncTime` / `isInBookshelf` 欄位一致。
- **改善方向**：共用同一 add book 路徑（書架 service 或 BookDao.add），`SessionFacade` 只做路由／狀態切換。
- **關聯影響**：書架 add book 流程、備份還原對 isInBookshelf 的處理。
- **驗證**：閱讀時把書加書架，書架顯示的書資訊與詳情頁一致；重開後 isInBookshelf 正確。

## X5【低】ContentTransformer 透過 compute() 跑 isolate，ReplaceRule 序列化穩定性影響規則引擎

- **位置**：`content/reader_v2_content_transformer.dart:21-46`
- **Tier**：T1（跨模組：規則引擎、替換規則）
- **問題**：使用 `ReplaceRule` 與 `ChineseTextConverter`，`ReplaceRule` 序列化穩定性直接影響規則引擎；未來若 `ReplaceRule` 加不可序列化欄位會導致 isolate 邊界崩潰。`ChineseTextConverter` 為 const 無狀態 OK。
- **改善方向**：`ReplaceRule` 加 isolate 邊界 serialize test；或改為傳可序列化 plain map 給 isolate。
- **關聯影響**：規則引擎替換規則模型、替換規則編輯器。
- **驗證**：替換規則變更後 isolate 仍正常接收應用；Add new field 時不會破壞 isolate 邊界。

## X6【低】ReaderChapterContentStorage / Store 在 repository 內每次 new

- **位置**：`content/reader_v2_chapter_repository.dart:231-247`
- **Tier**：T1（跨模組：核心服務章節內容快取）
- **問題**：`ReaderChapterContentStorage` / `Store` 在 repository 內每次 `new`，可能破壞核心服務層章節內容快取（每次都新建 instance，內部 in-memory cache 重置）。
- **改善方向**：DI 注入單例 instance；repository 只負責組合呼叫。
- **關聯影響**：核心服務章節內容快取、下載快取策略。
- **驗證**：同章重覆請求命中快取；不會因 repository 重建而 cache miss。