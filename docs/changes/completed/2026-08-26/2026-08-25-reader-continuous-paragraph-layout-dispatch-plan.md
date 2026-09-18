---
ROLE: relay-lead
CONTRACT: atlas/v3
MODEL: GPT-5.6-Luna
REASONING: Max
DELIVERY_POLICY: commit and push
REPORTING_LEVEL: technical
---

# 修正 Hybrid 連續段落排版

## Objective

讓 Hybrid 閱讀器保留 block 的 lazy loading／排程／admission 用途，但把 `ui.Paragraph` 的排版單位改成邏輯段落或其他穩定 layout unit，消除 block 邊界對文字排版造成的硬換行。相同邏輯段落無論如何切 block，都必須得到相同的換行、總高度、字元幾何與 anchor 座標，且不破壞真正段落邊界與既有 viewport 契約；不得引入跨獨立 Paragraph 的 continuation 偽抽象，也不得退化為整章一個 Paragraph。

## Task Packages

| # | Package | Route | Goal |
|---|---|---|---|
| 1 | `docs/changes/planning/2026-08-25-reader-continuous-paragraph-layout.md` | `claude-p` | 實作 block 與連續段落排版解耦，補齊跨 block 幾何與快取驗收 |

## Execution Order

只有一個 package，必須完整串行執行。這是跨 `TextPreprocessor`、`LayoutPump`、`ParagraphCache`、`DocumentIndex`、Hybrid render object 與測試的同一個排版契約，不能拆成互相獨立的平行修改。

## Parallel Groups

無。執行期間應避免另一個工作同時改動 reader hybrid 目錄或共用 Flutter build／test 資料。

## Shared Verification

合併後在 repository root 依序執行：

```text
flutter analyze
flutter test test/features/reader_v2/hybrid
flutter test test/features/reader_v2
flutter test
```

預期四項皆通過；relay 必須重新閱讀 diff，確認不是以關閉 lazy layout、刪除斷言、放寬 tolerance 或整章一次性排版來取得綠燈。

## Completion Protocol

relay 接受 package 後，將完整驗收輸出與實際變更填入 package 的 `Completion record`，將 package 與本 dispatch plan 移至 `docs/changes/completed/2026-08-25/`，追加當日 summary，然後依 Delivery Policy 將 source、tests 與 change records 一起 commit 並 push。若 worker 發現必須改變 `ReaderV2Location` schema、viewport controller 公開契約或 reader 模組邊界，先在 `Needs A Decision` 回報，不得自行擴大範圍。
