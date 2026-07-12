# 閱讀器底部選單重整 + 章內進度拖動條

## 需求（使用者原話摘要）

1. 底部主列 5 個按鈕（目錄、朗讀、換源、界面、設定）間距不對，應為 4 個——把「換源」納入「設定」。
2. 自動翻頁的速率控制也納入「設定」；速率要重做，最慢 8% 太快，要可以更慢。
3. 上一章／下一章中間的拖動條應改為調整「本章內位置」，不是跨數百章跳章。
4. 拖動過程中文字顯示重疊——希望可修復。

## Before（現況與診斷）

- `reader_v2_bottom_menu.dart`：主列固定 5 items（含換源），每個 `SizedBox(width: 70)` + `spaceEvenly`，在窄螢幕上擁擠；上方常駐一列「自動翻頁」速度 slider（clamp 0.08–0.45）。
- 「設定」按鈕開 `_ReaderAdvancedSheet`（進階設定：繁簡轉換＋點擊區域）；「界面」sheet 內已有一份重複的自動翻頁速度 slider（min 用 controller 常數 0.04，但 prefs 載入時 `_normalizeAutoPageSpeed` 又 clamp 到 0.08——實際下限被鎖在 8%）。
- 速度語意：`ReaderV2AutoPageController` 每 16ms tick 滾動 `viewportHeight × speed × elapsed`，即 speed=8% ≈ 12.5 秒滾完一個畫面高。
- 拖動條 value = 章節索引（0..chapterCount-1），`onScrubEnd` → `jumpToChapter`；幾百章的書一拖就跨章。跨章跳轉走 hybrid restore 鏈（DocumentIndex reset + 重新排版），期間畫面可能短暫出現新舊世界交錯的文字（使用者回報的「字重疊」最可能發生在這條路徑）。
- 全域設定頁 `reading_settings_page.dart` 也有一份「自動速度」slider（min 0.08）。

## After（改完的樣子）

1. **主列 4 items**：目錄、朗讀、界面、設定。「換源」改為進階設定 sheet 內的入口（本地書不顯示）。
2. **自動翻頁速度**移入進階設定 sheet；底部選單的常駐速度列移除（開始/停止自動翻頁的浮動按鈕保留）；界面 sheet 的重複速度列移除。
3. **速度下限放寬**：min 0.08/0.04 → 0.02（≈50 秒/畫面高），max 維持 0.45；1% 一格（divisions 43）。統一 `prefs_repository`、`settings_controller`、`auto_page_controller`、`reading_settings_page` 四處常數。
4. **拖動條改章內進度**：value = 本章百分比 0–100（未拖動時跟隨 `progressListenable.chapterPercent` 即時顯示）；拖動中顯示「本章 N%」標籤，放開才以字元比例換算 `charOffset`，經 `runtime.jumpToLocation`（既有 hybrid 路徑）跳到章內位置。上一章／下一章按鈕行為不變。
5. **字重疊**：拖動條不再觸發跨數百章的 restore；章內跳轉的 block 多半已載入、restore 極快，預期消除該場景的重疊。需真機回歸確認；若仍出現另開除錯任務。

## 變更點

- `features/menu/reader_v2_bottom_menu.dart` — 主列 4 items；移除速度列與換源按鈕；slider 改百分比 + progressListenable；`ReaderV2ChapterNavigationState` 改欄位（移除 scrubIndex/pendingIndex，加 scrubPercent）。
- `features/menu/reader_v2_menu_controller.dart` — scrub 狀態改 double percent；移除 pendingChapterNavigationIndex。
- `use_cases/reader_v2_page_coordinator.dart` — 新增 `jumpToCurrentChapterPercent(double)`：`loadContentAt` 取章長 → percent→charOffset → `jumpToLocation`（percent 0 對齊章首，比照 `_jumpHybridToChapter` 的 top-aligned 慣例）。
- `screen/reader_v2_page_shell.dart` / `screen/reader_v2_page.dart` — 佈線更新；`showAdvancedSettings` 增傳 `onChangeSource`。
- `features/settings/reader_v2_settings_sheets.dart` — 進階 sheet 加「換源」入口與「自動翻頁速度」區；界面 sheet 移除自動翻頁區。
- `features/settings/reader_v2_settings_controller.dart`、`features/settings/reader_v2_prefs_repository.dart`、`features/auto_page/reader_v2_auto_page_controller.dart`、`features/settings/reading_settings_page.dart`（settings_about 模組）— 速度下限常數統一為 0.02。
- 測試：更新 `reader_v2_page_shell_test.dart` 建構參數；`reader_v2_settings_controller_test.dart` 加下限 clamp 斷言；menu controller / coordinator 視縫隙補聚焦測試。

## 驗證

- `flutter analyze`、`flutter test`。
- 真機回歸（使用者）：4 按鈕間距、進階設定內換源/速度、最慢速度體感、章內拖動、拖動時是否仍有文字重疊。

## 狀態

- [x] 使用者確認方向（速度下限選 2%、整體照計畫進行）
- [x] 實作
- [x] 驗證：`flutter analyze` 無問題；`flutter test` 722 全過（含新增 3 個底部選單聚焦測試、2 個速度下限測試斷言）
- [ ] 真機回歸（使用者）：4 按鈕間距、進階設定內換源/速度、2% 最慢速度體感、章內拖動、拖動時文字重疊是否消失

## 後續調整（同日，使用者追加）

拖動條從「連續 0–100%、放開才跳」改為**十等份即時預覽**（對齊資訊列的 N/10 慣例）：

- Slider 加 `divisions: 10`；拖動中標籤改「本章 N/10」。
- 拖動跨檔位即觸發預覽跳轉：`ReaderV2PageCoordinator.previewChapterPercent`（180ms 防抖、`immediateSave: false` 不寫進度）；放開走 `commitChapterPercent`（取消未觸發預覽、跳轉並存進度）。
- 不逐格即時跳的理由：章內跳轉走 hybrid restore 鏈（重設 DocumentIndex），拖動 onChanged 頻率高，逐格會高頻重建排版世界——jank 且放大既有重疊 bug 面。十等份 + 防抖把一次拖動的跳轉上限鎖在個位數。
- percent 0 檔位改直接 `jumpToLocation(charOffset 0 + anchorOffsetInViewport)` 的 top-aligned 慣例（原 `jumpToChapter` 不支援 immediateSave 參數）。
- 驗證：analyze 乾淨、`flutter test` 722 全過（底部選單測試更新為檔位斷言）。
