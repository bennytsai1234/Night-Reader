# 05 — 使用者體驗

> 範圍：Reader V2 模組的使用者體驗問題。共 8 條。

## U1【中】Auto page 遇 placeholder isLoading 立刻停止

- **位置**：`features/auto_page/reader_v2_auto_page_controller.dart:94-98`
- **Tier**：T1
- **問題**：slide 模式 `_step` 直接 `moveToNextPage`，鄰頁是 placeholder（`isLoading`）時回 false，auto page 立刻 stop，使用者感覺自動翻頁突然停了。
- **改善方向**：placeholder `isLoading` 時 auto page 應等 `ensureSlideNeighborReady` 完成而非立刻 stop；給短暫等待／重試。
- **驗證**：auto page 在章節邊界不會瞬間中斷；連續自動翻頁跨章順暢。

## U2【低】TTS sheet 單一按鈕狀態不清

- **位置**：`features/tts/reader_v2_tts_sheet.dart:33-81`
- **Tier**：T1
- **問題**：UI 用「`isPlaying ? '暫停' : '從目前位置朗讀'`」單一按鈕切換 toggle，但 toggle 內部分 play/pause/resume/start 四種狀態，UI 顯示都一樣；無「前進/後退一句」、無進度顯示。
- **改善方向**：分開 play/pause/resume 按鈕或更明確圖示；顯示 segment index/total；加「前進/後退一句」按鈕。
- **驗證**：TTS 操作意圖清晰；使用者能跳句、能看進度。

## U3【低】TTS 音調/語速 slider 拖動即寫 prefs

- **位置**：`features/tts/reader_v2_tts_sheet.dart:59-76`；`features/tts/reader_v2_tts_controller.dart:222-243`
- **Tier**：T0
- **問題**：TTS slider 拖動時即時 `setRate/setPitch`，每次都 `prefs.setDouble` 寫 SharedPreferences，主 isolate 卡頓。介面設定 sheet 已用 debounce + `onChangeEnd` pattern，TTS sheet 沒對齊。
- **改善方向**：`onChanged` 只 update in-memory + notify，`onChangeEnd` 才寫 prefs。
- **驗證**：slider 拖動流暢；放開後才寫入 prefs。

## U4【低】章節抽屜首次開啟不定位當前章節

- **位置**：`shell/reader_v2_chapters_drawer.dart:37-40, 67-80`
- **Tier**：T0
- **問題**：`_scheduleScrollToCurrentChapter` 在 `didChangeDependencies` 排程，但 Drawer 是 `Scaffold` drawer，第一次打開才 build，`hasClients=false` 會略過——第一次打開目錄不會自動定位到當前章節。
- **改善方向**：在 drawer `onOpened` 或 `ScrollController` 首次有 clients 時再 schedule。
- **驗證**：開書讀幾章後打開目錄，自動捲到當前章節。

## U5【低】_PermanentInfoBar 與 TopMenu 書名重複

- **位置**：`shell/reader_v2_page_shell.dart:227-290`；`features/menu/reader_v2_top_menu.dart:98-149`
- **Tier**：T0
- **問題**：`_PermanentInfoBar` 永遠顯示書名 + 頁碼；`ReaderV2TopMenu` `controlsVisible` 時顯示書名 + 章節名。`controlsVisible` 時兩者同時顯示，書名上下重複。
- **改善方向**：`controlsVisible` 時隱藏 `_PermanentInfoBar` 的書名部分，或改由 TopMenu 接管顯示。
- **驗證**：選單顯示時書名不重複；隱藏時仍有頁碼資訊。

## U6【低】showReadTitleAddition 永遠 true

- **位置**：`features/settings/reader_v2_settings_controller.dart:43`
- **Tier**：T0
- **問題**：`bool get showReadTitleAddition => true;` 永遠 true，但名稱暗示可設定；`readStyleFor` 用此決定扣 bottom padding，讀者永遠下方有一條資訊列。
- **改善方向**：接上 `SharedPreferences` 設定（讓使用者可關），或拿掉 getter 直接以 true 內聯取代，避免誤導。
- **驗證**：設定可關／開資訊列；關閉時不扣 padding。

## U7【低】章節抽屜無搜尋／進度條

- **位置**：`shell/reader_v2_chapters_drawer.dart`
- **Tier**：T1
- **問題**：無搜尋、無進度條，長篇 1000+ 章節難定位。
- **改善方向**：加搜尋 `TextField` + `filter`；加進度 `SliderTheme` 或目前位置指示；加「捲動到目前」FAB。
- **驗證**：長篇能快速搜尋定位；進度條能看出閱讀章節位置。

## U8【低】_TopSystemInfoBar 吃掉 status bar 區 tap

- **位置**：`shell/reader_v2_page_shell.dart:124-135, 216-225`
- **Tier**：T0
- **問題**：`_TopSystemInfoBar` 是空 `ColoredBox` 但吃掉 status bar 區域 tap，讀者上緣 tap 無法喚起閱讀內容 tap（無法喚出選單）。
- **改善方向**：保留做 status bar 背景，但 tap 應穿透或 also 觸發 content tap。
- **驗證**：上緣 tap 能喚出選單或翻頁（依使用者設定）。