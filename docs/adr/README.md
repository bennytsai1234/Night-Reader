# 架構決定（ADR）索引

一份 ADR 記一個定案：為什麼這樣定、考慮過什麼、否決了什麼、後果是什麼。使用者說「(adr)」或「寫進 ADR」就是要寫一份。要推翻就改寫或另寫一份取代，並在被取代的那份開頭標上「已由 ADR xxxx 取代」；不刪舊的。檔名 `NNNN-slug.md`，編號不重複（CI 會檢查）。新增後把它加進下面的索引。

## 原則：怎麼取捨

| ADR | 一句話 |
|---|---|
| [0023](0023-optimize-for-smoothness-not-waiting-time.md) | 不以縮短等待時間為目標，看整體流暢與動畫完整 |
| [0018](0018-animations-never-share-frames-with-heavy-work.md) | 動畫播放時不跑會佔住主執行緒的工作，寧可內容晚一點出現 |
| [0029](0029-no-dropped-frames-in-transitions-and-reveals.md) | 轉場與骨架換場不掉幀的六個做法 |
| [0022](0022-glass-moves-content-fades.md) | 一個元件的進出場只做一件事：玻璃只動、內容只淡，最後一幀等於靜止 |
| [0009](0009-no-explanatory-copy-in-ui.md) | 介面不放解釋性文案 |
| [0030](0030-settings-hierarchy-and-option-inventory.md) | 設定的分級規則與全部選項的去留 |

## 開 App 與載入

| ADR | 一句話 |
|---|---|
| [0017](0017-launch-straight-to-shelf.md) | 開 App 不放開場畫面，系統啟動畫面只有書架底色 |
| [0025](0025-launch-entrance-and-skeletons-grow-in.md) | 開 App 先只有底色再進場；骨架出現也照骨架換場 |
| [0024](0024-skeleton-drawn-from-last-screen.md) | 骨架照上次的畫面畫，骨架換場由左而右 |
| [0016](0016-reader-skeleton-from-the-real-page.md) | 閱讀器的正文骨架照一頁真正的行畫 |

## 介面與動畫

| ADR | 一句話 |
|---|---|
| [0011](0011-no-large-titles.md) | 頁首一律置中小標題，不用大標題 |
| [0012](0012-no-cover-expand-book-open.md) | 從書架開書不做封面放大轉場 |
| [0015](0015-my-tab-rows-are-navigation-only.md) | 「我的」分頁只放入口，不放開關 |
| [0020](0020-chosen-transition-everywhere.md) | 選定的換頁動畫用在每一種換頁，拖曳返回與點分頁也一樣 |
| [0021](0021-covers-are-plain-images.md) | 封面只畫圖片，不做成像一本書 |

## 正文排版

| ADR | 一句話 |
|---|---|
| [0007](0007-latin-runs-snap-to-half-cells.md) | 英數字段補到半格，emoji 佔一格 |
| [0019](0019-justify-by-spreading-residual-into-letter-spacing.md) | 左右對齊把湊不滿一格的空隙攤進字距 |
| [0026](0026-kinsoku-spreads-into-the-pulled-line.md) | 換行做避頭尾，被拉字的那一行把空隙攤進字距（取代 0005） |
| [0006](0006-tap-page-turn-scrolls-one-screen.md) | 點擊翻頁就是捲動一屏，不做分頁模式 |

## 書源與下載

| ADR | 一句話 |
|---|---|
| [0028](0028-source-work-in-a-source-isolate.md) | 書源工作在常駐的書源 isolate 執行；Cookie 與限流留在主 isolate |
| [0008](0008-shelf-books-download-whole-book.md) | 書架上的網路書整本下載，不限網路、沒有開關 |
| [0013](0013-no-source-login-or-interactive-verification.md) | 書源不支援登入與互動驗證 |

## 工程與流程

| ADR | 一句話 |
|---|---|
| [0001](0001-maintain-third-party-plugin-forks.md) | 自行維護 flutter_tts、flutter_js、file_picker 三個 fork |
| [0002](0002-build-and-release-only-in-github-actions.md) | 建置與發布只在 GitHub Actions，tag 只由 CI 建立 |
| [0003](0003-android-arm64-only.md) | Android 只發布 arm64-v8a，iOS 只附未簽章 IPA |
| [0027](0027-beta-branch-and-fast-forward-main.md) | 日常改動進 beta、合併就發測試版；main 只快轉發正式版 |
| [0014](0014-manual-beta-and-squash-prs.md) | PR 的審查、squash 合併、交接與原型分支（分支與發版時機已由 0027 取代） |
| [0010](0010-release-notes-from-chinese-changelog.md) | Release 說明由中文 CHANGELOG 提供，發版前檢查一定要寫 |

## 已取代

| ADR | 取代它的 |
|---|---|
| [0005](0005-no-kinsoku-line-breaking.md) 正文換行不做避頭尾 | 0026 |
| [0004](0004-beta-channel-from-every-main-merge.md) 每次合併到 main 自動發測試版 | 0014、0027（tag 與 versionCode 的算法照本文） |
