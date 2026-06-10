# 介紹網站重新設計 — 夜讀者的書房

## 任務類型

Feature（網站介面全面重新設計；不涉及 App 程式碼）。紀律等級 T1。

使用者明確授權設計方向（「想怎麼設計都按你喜歡的來」），視為之前/之後的預先確認。

## 確認的之前

`website/index.html` 是一頁深棕色調的通用 landing page：置中 hero、12 張等寬功能卡片、技術標籤、CTA、footer。設計語言偏 SaaS 模板，缺乏與「夜讀中文長篇小說」產品氣質的連結；亦缺少 meta description、Open Graph、favicon 等基本 SEO/分享標籤。

## 確認的之後

同一檔案（`website/index.html`，單檔、零建置、部署流程不變）改為「夜讀者的書房」編輯式設計：

1. **視覺語言**：深墨藍夜空底色 + 暖燈光金主色 + 月白冷色輔助 + 硃砂印章紅點綴；標題改用 Noto Serif TC（書卷感），直排文字（writing-mode: vertical-rl）作為章節標記（卷一〜終卷），footer 配硃砂「夜讀」印章。
2. **Hero**：CSS 星空 + 月暈、詩意標語「把長夜，留給長篇。」、App icon、GitHub API 即時版本徽章、雙 CTA。
3. **互動排版示範（核心亮點）**：手機框 mockup 內排版魯迅《秋夜》（公版文本），旁有即時生效的控制項 — 字號、行高、字體（明體/黑體）、閱讀主題（夜間/羊皮/松煙），以 CSS 變數驅動；附「網頁模擬示意」誠實註記。
4. **Bento 功能格**：TTS（逐詞高亮動畫 + 波形）與多書源搜尋（mock 結果）兩張大卡 + 其餘 9 項功能小卡；原 12 項功能全數保留（排版引擎由示範區呈現）。
5. **書源自主三步驟** + 純工具定位聲明；誠實數據列（0 廣告 / 0 追蹤 / 100% 開源，已查證 pubspec 無任何廣告/分析 SDK）。
6. **開源工藝區**：GPL-3.0 聲明 + 技術標籤。
7. **下載區**：GitHub API 抓最新版本與 arm64-v8a APK 直連、Android 7.0+（minSdk 24）需求說明。
8. **保留並強化的機能**：手機選單、捲動 reveal、prefers-reduced-motion、onerror 圖片 fallback；新增 meta description / Open Graph / Twitter card / favicon / theme-color / canonical。

## 預期的檔案範圍

- `website/index.html`（全面重寫）
- `website/app-icon.png`（沿用，不變）
- 本計畫檔

## 驗證步驟

1. Python `html.parser` 完整解析無錯誤（標籤閉合正確）。
2. 抽出 `<script>` 內容以 `node --check` 驗證 JS 語法。
3. 交叉檢查：所有 `href="#…"` 錨點皆有對應 `id`；本地資源（app-icon.png）存在。
4. 以 Node 快速 DOM 煙霧測試（jsdom 不可用時改用字串斷言）：版本元素、下載按鈕、示範控制項等關鍵 id 存在。

## 回退路徑

`git revert` 本次 commit 即可完整還原舊版網站；部署僅在 main 分支觸發，本分支不影響線上。

## 驗證結果（2026-06-10）

1. Python `html.parser` 完整解析：通過（標籤閉合、無錯位）。
2. `node --check` 驗證抽出的 inline JS：通過。
3. 錨點/id 交叉檢查：通過；本地資源 `app-icon.png` 存在；JSON-LD 可解析。
4. Playwright 截圖驗證（桌面 1440px 全頁、#typeset、#features、手機 390px 全頁）：各區段渲染正常，互動排版示範、TTS 逐詞高亮、bento 版面、單欄收合皆如預期；過程中修正手機版標題斷行（`text-wrap: balance`）與副標 `<br>` 孤字問題。
