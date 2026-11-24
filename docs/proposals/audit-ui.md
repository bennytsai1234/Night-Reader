# 全面檢查：介面

把「介面」四段程式（`docs/agents/auto-audit.md`「舊程式」表上的介面 0–3）全部讀一遍，列出讀者會碰到的錯；只讀、只列，不修。每一筆都從觸發點走到出錯的那一行，查過以前的 issue 沒報過。

- 讀的範圍：`lib/shared/widgets/`（含 `skeleton/`）、`lib/shared/navigation/`、`theme/`、`layout/`；`lib/features/bookshelf/`、`book_detail/`、`home/`、`settings/`、`about/`、`association/`、`replace_rule/`。
- 讀的 SHA：`fff55f9c3ad30947f9b3d76012fb84989d98c095`（`origin/beta`），下面的「檔案:行號」都是這個提交的。
- 標準照 `docs/agents/auto-audit.md`「各方面看什麼」「算問題的」「不報的」；每一段都讀完，不設筆數上限。

## 進度

| 段 | 讀了哪些檔 | 找到幾筆 |
|---|---|---|
| 介面 0 | `lib/shared/widgets/skeleton/` 11 個檔 | 0 |

## 問題

### 介面 0：骨架

沒有找到。讀過的地方：骨架呼吸的計時與收住（`skeleton.dart`）、開 App 進場的兩條時間線與等待（`launch_entrance.dart`）、定格換場拍圖與放圖（`snapshot_sweep.dart`）、骨架換場的兩層與等封面（`skeleton_switcher.dart`、`sliver_skeleton_switcher.dart`、`skeleton_reveal.dart`、`cover_reveal.dart`）、照字畫長條與標點量測（`skeleton_text.dart`、`grouped_list_skeleton.dart`、`skeleton_shapes.dart`）。計時器、監聽、控制器與拍下的圖都有對應的取消或放掉；非同步回來前都核對還是不是同一輪、元件還在不在。

## 拿不準

（目前沒有）
