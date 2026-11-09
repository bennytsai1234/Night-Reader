# 架構決定（ADR）索引

一份 ADR 記一個定案：為什麼這樣定、考慮過什麼、否決了什麼、後果是什麼。使用者說「(adr)」或「寫進 ADR」就是要寫一份。要推翻就改寫或另寫一份取代，並在被取代的那份開頭標上「已由 ADR xxxx 取代」，留著它自己的理由；整份內容併進另一份的，刪掉舊的，歷史留在 git。檔名 `NNNN-slug.md`，編號不重複（CI 會檢查）。新增後把它加進下面的索引。

## 原則：怎麼取捨

| ADR | 一句話 |
|---|---|
| [0023](0023-optimize-for-smoothness-not-waiting-time.md) | 不以縮短等待時間為目標，看整體流暢與動畫完整 |
| [0018](0018-animations-never-share-frames-with-heavy-work.md) | 動畫播放時不跑會佔住主執行緒的工作，寧可內容晚一點出現 |
| [0029](0029-no-dropped-frames-in-transitions-and-reveals.md) | 轉場與骨架換場不掉幀：用時間換流暢、工作拆小分攤到更多格，與六個做法 |
| [0036](0036-three-rules-for-smooth-animation.md) | 動畫流不流暢的三條標準：點下去那一幀可以重、預留停頓可以跑重工作、動畫中每一幀在 8.3ms 內（電腦 4.2ms）；使用者在手機上感覺得到才修 |
| [0037](0037-smoothness-strategy-per-scene.md) | 每種場景用定好的流暢策略（靜止時準備、只播不做事、等靜止再放、每幀限量、只平移裁切）；掉幀是畫面在變時超過上限 |
| [0022](0022-glass-moves-content-fades.md) | 一個元件的進出場只做一件事：玻璃只動、內容只淡，最後一幀等於靜止 |
| [0009](0009-no-explanatory-copy-in-ui.md) | 介面不放解釋性文案 |
| [0030](0030-settings-hierarchy-and-option-inventory.md) | 設定的分級規則與全部選項的去留 |

## 開 App 與載入

| ADR | 一句話 |
|---|---|
| [0017](0017-launch-straight-to-shelf.md) | 開 App 不放開場畫面，系統啟動畫面只有書架底色 |
| [0025](0025-launch-entrance-and-skeletons-grow-in.md) | 開 App 先只有底色再進場；骨架出現也照骨架換場 |
| [0031](0031-launch-reveal-crossfades-two-still-pictures.md) | 開 App 書架換場是兩張定格畫面的交叉淡換：用時間與記憶體換流暢與穩定（準備書架的時機已由 0035 改到呼吸前） |
| [0035](0035-launch-prepares-shelf-before-breathing.md) | 開 App 在骨架長完、呼吸之前就建好書架並拍好兩張定格畫面；定格畫面用一般的畫法拍 |
| [0024](0024-skeleton-drawn-from-last-screen.md) | 骨架照上次的畫面畫，骨架換場由左而右 |
| [0041](0041-skeleton-breath-shared-gradient.md) | 骨架呼吸的漸層每個骨架每幀一道，形狀照舊各自畫；否決整個骨架蓋遮罩與開 App 整段定格畫面 |
| [0016](0016-reader-skeleton-from-the-real-page.md) | 閱讀器的正文骨架照一頁真正的行畫 |

## 介面與動畫

| ADR | 一句話 |
|---|---|
| [0011](0011-no-large-titles.md) | 頁首一律置中小標題，不用大標題 |
| [0012](0012-no-cover-expand-book-open.md) | 從書架開書不做封面放大轉場 |
| [0015](0015-my-tab-rows-are-navigation-only.md) | 「我的」分頁只放入口，不放開關 |
| [0020](0020-chosen-transition-everywhere.md) | 選定的換頁動畫用在每一種換頁，拖曳返回與點分頁也一樣 |
| [0021](0021-covers-are-plain-images.md) | 封面只畫圖片，不做成像一本書 |
| [0040](0040-day-and-night-styles-pure-black.md) | 淺色、深色各選一個風格，深色預設純黑（可關），風格精簡成六種 |

## 正文排版

| ADR | 一句話 |
|---|---|
| [0007](0007-latin-runs-snap-to-half-cells.md) | 英數字段補到半格，emoji 佔一格 |
| [0019](0019-justify-by-spreading-residual-into-letter-spacing.md) | 左右對齊把湊不滿一格的空隙攤進字距 |
| [0026](0026-kinsoku-spreads-into-the-pulled-line.md) | 換行做避頭尾，被拉字的那一行把空隙攤進字距（取代 0005） |
| [0006](0006-tap-page-turn-scrolls-one-screen.md) | 點擊翻頁就是捲動一屏，不做分頁模式 |
| [0043](0043-reader-weight-title-and-info-size-are-settings.md) | 正文粗細、章節標題粗細與對齊、頁首頁尾字級是閱讀設定（使用者點名要調，不照「選定即固定」） |
| [0045](0045-fonts-downloaded-on-pick.md) | 正文與介面字型可選（系統、思源宋體、霞鶩文楷），選了才下載、核對 SHA-256；英數字照舊用系統字型 |

## 書源與下載

| ADR | 一句話 |
|---|---|
| [0032](0032-epub-read-as-text-converted-on-import.md) | EPUB 只讀文字，匯入時轉成純文字，之後照 TXT 讀；目錄太粗時照 TXT 的章名規則再切 |
| [0028](0028-source-work-in-a-source-isolate.md) | 書源工作在常駐的書源 isolate 執行；Cookie 與限流留在主 isolate（條數已由 0034 改成四條） |
| [0034](0034-rule-js-waits-synchronously.md) | 規則 JS 等網路時整條書源 isolate 停住、拿到的就是結果，和 Legado 一樣；書源 isolate 開四條，網路 isolate 替它們做要等的事 |
| [0008](0008-shelf-books-download-whole-book.md) | 書架上的網路書整本下載，不限網路、沒有開關 |
| [0038](0038-source-login-in-the-foreground.md) | 書源照 Legado 登入（網頁登入與書源的表單），只在使用者打開的登入頁裡進行，背景從不等人；「需要登入」「需要在網頁驗證」是狀態不是壞掉，閱讀器在失敗處給登入與前往驗證的路 |
| [0039](0039-multi-device-sync.md) | 多台手機同步：Google 雲端硬碟或 WebDAV 都能用，每筆資料各自比時間合併、刪除也同步；備份與同步都帶登入資料（什麼時候同步已由 0046 改寫） |
| [0046](0046-daily-sync-is-progress-only.md) | 日常只同步閱讀進度，其他資料按「立即全面同步」才同步、期間鎖住 App；合併計算在背景 isolate |
| [0042](0042-bookmarks-follow-the-book-not-the-source.md) | 書籤跟著書名加作者、不跟書源，位置和閱讀進度同一套（章名＋第幾個字＋錨點）；換源跟著搬、同步與備份都帶 |
| [0044](0044-highlights-mark-content.md) | 標註記畫到的字與顏色、樣子，位置與跟著書走的方式同書籤；從選字選單「⋮」畫，點了換顏色、寫備忘或刪除，可匯出 Markdown |
| [0033](0033-cloudflare-checks-pass-in-a-hidden-browser.md) | Cloudflare 檢查由看不到的瀏覽器自動通過，要真人勾選的網站當成不能用；書源校驗在同樣環境的 worker 執行 |
| [0051](0051-source-kinds-follow-the-source-type.md) | 書源分成小說、漫畫、有聲，只看類型欄位：匯入照名稱字樣補判、校驗照正文改，手動也能改；漫畫、有聲源留著不停用，影視、文件照舊可刪 |
| [0053](0053-same-title-different-kind-is-a-different-book.md) | 同名不同類是不同的書：書的類別照書源寫，認書的鍵在漫畫、有聲前加類別，換源只列同一類，書源改了類型書跟著改 |

## 工程與流程

| ADR | 一句話 |
|---|---|
| [0049](0049-development-and-release-flow.md) | 開發與發布流程：分支、收尾與合併、審查、CI、測試版與正式版、版號 |
| [0001](0001-maintain-third-party-plugin-forks.md) | 自行維護 flutter_tts、flutter_js、file_picker 三個 fork |
| [0002](0002-build-and-release-only-in-github-actions.md) | 建置與發布只在 GitHub Actions，tag 只由 CI 建立 |
| [0003](0003-android-arm64-only.md) | Android 只發布 arm64-v8a，iOS 只附未簽章 IPA |

## 已取代

| ADR | 取代它的 |
|---|---|
| [0005](0005-no-kinsoku-line-breaking.md) 正文換行不做避頭尾 | 0026 |
| [0013](0013-no-source-login-or-interactive-verification.md) 書源不支援登入與互動驗證 | 0038（背景工作不等人照本文） |
