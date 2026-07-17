# Flutter 3.44.6 升級後排版探針回歸（打磨方向 5）

層級：T0（純驗證，未發現行為變化，無程式碼變更）

## 驗證內容與結果

對照 `docs/changes/completed/2026-07-12/2026-07-12-reader-typography-redesign.md`
「已實測驗證的引擎事實」表與 2026-07-13 探針紀錄，在 Flutter 3.44.6 下
重跑 `docs/scratchpad/2026-07-13-justify-indent-probe/justify_probe_test.dart`：

| 項目 | 3.44.0 結論 | 3.44.6 實測 | 一致 |
|---|---|---|---|
| justify 折疊行首 U+3000 | 縮排壓成 0 寬、每字 20→23.4px | w=0.0、23.4px | ✅ |
| placeholder 縮排 + justify | 縮排保持 20px、正文 +0.6px/字、行高 30 不變 | 完全相同 | ✅ |
| 單行段落（hardBreak） | 不受 justify 影響 | 相同 | ✅ |
| 末行補償舊分母公式（gaps） | 近滿末行回捲成 4 行（bug 實證用） | lineCount=4 | ✅ |

- `flutter analyze`：No issues found。
- `flutter test`：734 全過（本次回歸時點；後續同日變更增至 736）。

結論：SkParagraph 在 3.44.6 下的 justify / placeholder / letterSpacing
行為與 3.44.0 實證完全一致，handoff 文件的引擎事實表無需更新。
真機目視回歸（縮排、justify、B2、TTS 高亮、進度恢復）留待下次
release 驗收一併執行。
