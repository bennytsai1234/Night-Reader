# 全面檢查：介面

把「介面」四段程式（`docs/agents/auto-audit.md`「舊程式」表上的介面 0–3）全部讀一遍，列出讀者會碰到的錯；只讀、只列，不修。每一筆都從觸發點走到出錯的那一行，查過以前的 issue 沒報過。

- 讀的範圍：`lib/shared/widgets/`（含 `skeleton/`）、`lib/shared/navigation/`、`theme/`、`layout/`；`lib/features/bookshelf/`、`book_detail/`、`home/`、`settings/`、`about/`、`association/`、`replace_rule/`。
- 讀的 SHA：`fff55f9c3ad30947f9b3d76012fb84989d98c095`（`origin/beta`），下面的「檔案:行號」都是這個提交的。
- 標準照 `docs/agents/auto-audit.md`「各方面看什麼」「算問題的」「不報的」；每一段都讀完，不設筆數上限。

## 進度

| 段 | 讀了哪些檔 | 找到幾筆 |
|---|---|---|
| 介面 0 | `lib/shared/widgets/skeleton/` 11 個檔 | 0 |
| 介面 1 | `lib/shared/widgets/` 其餘 35 個檔（`glass/`、`lists/`、`popups/`、`book/`、`text/` 與根目錄 4 個）、`lib/shared/navigation/` 10 個、`theme/` 9 個、`layout/` 2 個，共 56 個 | 1 |

## 問題

### 介面 0：骨架

沒有找到。讀過的地方：骨架呼吸的計時與收住（`skeleton.dart`）、開 App 進場的兩條時間線與等待（`launch_entrance.dart`）、定格換場拍圖與放圖（`snapshot_sweep.dart`）、骨架換場的兩層與等封面（`skeleton_switcher.dart`、`sliver_skeleton_switcher.dart`、`skeleton_reveal.dart`、`cover_reveal.dart`）、照字畫長條與標點量測（`skeleton_text.dart`、`grouped_list_skeleton.dart`、`skeleton_shapes.dart`）。計時器、監聽、控制器與拍下的圖都有對應的取消或放掉；非同步回來前都核對還是不是同一輪、元件還在不在。

### 介面 1：共用元件、換頁、主題、版面

#### 1-1. 不能切的開關比其他灰掉的東西淡一倍多，幾乎看不見

**會發生什麼**：「關於夜讀」把「解鎖才能打開」設成會鎖之後，「離開時蓋住畫面」那一列灰掉；列的字是規定的灰（不透明度 0.4），列尾的開關卻只剩 0.16，比其他灰掉的開關淡得多，看起來像沒有開關。`DESIGN.md` 原則 5 與 `docs/design/components.md`「選單與提示」定的是灰掉全 App 只有一種樣子、開關「軌道留著顏色只降透明度」。

**為什麼**：

1. 觸發點：`lib/features/about/about_page.dart:306-314`，「離開時蓋住畫面」的開關列在鎖開著時給 `enabled: !locking`，也就是 `false`。
2. 開關列把停用同時交給整列和開關：`lib/shared/widgets/lists/grouped_row.dart:466-478`。

   ```dart
   final active = enabled && onChanged != null;
   return GroupedRow(
     ...
     enabled: enabled,
     ...
     trailing: GroupedSwitch(
       value: value,
       onChanged: active ? onChanged : null,
     ),
   ```

3. 整列停用時整列包一層 0.4：`grouped_row.dart:325-327`。

   ```dart
   if (!enabled) {
     row = Opacity(opacity: AppDisabled.opacity, child: row);
   }
   ```

4. 開關拿不到 `onChanged` 也自己再包一層 0.4：`grouped_row.dart:436-439`。

   ```dart
   child: Opacity(
     opacity: enabled ? 1 : AppDisabled.opacity,
     child: track,
   ),
   ```

   兩層疊起來是 0.4 × 0.4 = 0.16。只有開關自己停用（列沒停用）的地方是 0.4，所以同一種「不能切」有兩種淡法。

**怎麼確認**：在 `test/shared/widgets/disabled_look_test.dart` 加一項：放一列 `GroupedSwitchRow(enabled: false, value: true, onChanged: (_) {})` 和一顆單獨的 `GroupedSwitch(value: true, onChanged: null)`，照檔裡 `shownColor` 的做法把每顆開關祖先的 `Opacity` 乘起來，斷言兩者都是 `AppDisabled.opacity`。

**修法方向**：修在開關列：整列已經降透明度時，裡面的開關只拿掉點擊、不再自己降一次（例如開關列交給開關時標明「外面已經灰掉了」）。同一個原因的其他地方一起看：`GroupedRow(enabled: false)` 的列尾若放了自己會灰掉的控件（`GroupedSwitch`、用 `context.actionColor` 的 `GlassIconButton`、`GlassCapsule`），都會疊成 0.16；`GroupedRow` 只在一處（`grouped_row.dart:325`）處理整列，可以在那裡讓列尾不再重複。

**輕重**：畫面錯。

## 拿不準

（目前沒有）
