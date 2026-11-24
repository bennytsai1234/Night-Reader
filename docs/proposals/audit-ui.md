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
| 介面 2 | `lib/features/bookshelf/` 10 個、`book_detail/` 19 個、`home/` 2 個，共 31 個 | 2 |
| 介面 3（未完） | 讀完 `lib/features/settings/` 14 個、`about/` 11 個、`association/` 6 個；**`replace_rule/` 5 個還沒讀** | 1 |

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

### 介面 2：書架、書籍詳情、主頁

#### 2-1. 自訂排序時拖一本書換位置，會蓋掉背景剛查到的新章節，偶爾還把拖好的書放回別的位置

**會發生什麼**：開 App 後書架在背景檢查更新的那段時間裡（下拉檢查也一樣），在自訂排序下拖一本書放下，已經查完的書的新章節數、最新章節、檢查時間被寫回舊的值：檢查結束後角標寫「+N」，進度線與書籍詳情的「最新章節」卻還是舊的，下次檢查又報一次同樣的新章節。放下的那一刻若剛好有一次書架重讀（某本書下載完成、自動換源、同步套用了進度），存下的順序照重讀回來的混合順序算，拖的那本跳到別的位置。

**為什麼**：

1. 觸發點：`lib/features/bookshelf/bookshelf_page.dart:847-876`，放下時呼叫 `provider.reorderBooks(from, to)`。
2. 排序把書架上每一本書照記憶體裡的樣子整筆寫回：`lib/features/bookshelf/provider/bookshelf_logic_mixin.dart:180-185`。

   ```dart
   final item = books.removeAt(oldIndex);
   books.insert(newIndex, item);
   for (var i = 0; i < books.length; i++) {
     books[i].order = i;
     await bookDao.upsert(books[i]);
   }
   ```

   `upsert` 是整列覆蓋（`lib/core/database/dao/book_dao.dart:76-77`，`insertOnConflictUpdate`），不是只改順序。
3. 背景檢查每查完一本就把新的章節數、最新章節與檢查時間寫進資料庫：`lib/core/download/book_update_service.dart:139-177`（寫回前讀資料庫最新的一筆、只換書源給的欄位，`await bookDao.upsert(info)`）。書架記憶體裡的書要等整批查完才重讀：`lib/features/bookshelf/provider/bookshelf_update_mixin.dart:110-130`（`await loadBooks()` 在最後）。這段期間記憶體裡是查之前的書，第 2 步整筆寫回就把查到的蓋掉。
4. 第 2 步的迴圈每一圈都重讀 `books` 這個欄位；途中若有一次重讀做完，欄位換成資料庫照混合順序排出來的新清單（`lib/features/bookshelf/bookshelf_provider.dart:121`，`books = await bookDao.getInBookshelf(); _sortBooks();`），迴圈接著把 0、1、2… 寫進新清單的書，存下的就是那份混合的順序。重讀的來源有下載完成（`lib/core/download/download_executor.dart:542`）、自動換源、進度同步。

**怎麼確認**：在 `test/features/bookshelf/` 加一個 provider 測試：書架兩本書 A、B，切到自訂排序；不經書架、直接用 `BookDao` 把 A 的章節數改大（模擬背景檢查寫回）；呼叫 `reorderBooks(1, 0)`，斷言資料庫裡 A 的章節數是改大的值、順序是 B、A。再一項：讓 `upsert` 第一次寫入時插一次 `loadBooks()`（假的 `BookDao`），斷言最後存下的順序仍是拖好的順序。

**修法方向**：修在排序：只寫順序，不整筆寫回；用放下那一刻的清單算好每本的新順序，一次在同一個交易裡寫進去（`BookDao` 加一個只改 `order` 的方法），迴圈不再讀會被重讀換掉的欄位。同一個原因（拿記憶體裡的書整筆寫回）在書籍詳情也有：`lib/features/book_detail/book_detail_provider.dart:1155-1158` 存封面後 `await _bookDao.upsert(_book)`，要等封面下載完才寫，這段期間背景檢查寫進去的欄位同樣會被蓋掉；一起改成只寫封面的欄位。

**輕重**：資料遺失或寫壞。

#### 2-2. 書籍詳情的「換封面」面板打開時先出現置中轉圈，每張候選封面載入時也各轉一個圈

**會發生什麼**：打開「換封面」，面板滑上來時中間是一個轉圈，接著才換成封面格子；每張網路上找到的候選封面在圖到之前各自轉圈，圖到了一幀冒出來。規格是整區載入用骨架、不放置中轉圈（`DESIGN.md` 原則 4、`docs/design/components.md`「狀態視圖」），封面載入中鋪骨架的底色、圖片到了淡入（`docs/design/components.md`「封面」）。

**為什麼**：

1. 觸發點：書籍詳情「⋯」選單的「換封面」，`lib/features/book_detail/book_detail_page.dart:1171-1179` 打開面板。
2. 面板一建立就開始讀資料庫裡存過的封面與繁簡字典，讀完才算準備好：`lib/features/book_detail/change_cover_provider.dart:98-112`。
3. 還沒準備好時整個格子區是置中轉圈：`lib/features/book_detail/change_cover_sheet.dart:143-145`。

   ```dart
   if (!provider.isInitialized) {
     return const Center(child: CircularProgressIndicator());
   }
   ```

4. 每張候選封面用 `CachedNetworkImage`，佔位是轉圈、圖到了沒有淡入：`lib/features/book_detail/widgets/cover/cover_grid_item.dart:47-55`。

**怎麼確認**：在 `test/features/book_detail/` 打開換封面面板（`ChangeCoverProvider` 換成讀資料庫要等一下的假資料），在 `init` 完成前 `pump` 一幀，斷言面板裡沒有 `CircularProgressIndicator`；放一張還沒載完的網路封面，斷言它的格子也沒有 `CircularProgressIndicator`。

**修法方向**：準備好之前直接畫格子（第一格「恢復預設」一開始就有），或照格子的樣子畫骨架；候選封面改用 App 共用的封面元件（`BookCoverWidget`，載入中鋪骨架底色、到了淡入）。

**輕重**：畫面錯。

### 介面 3：設定、關於、檔案關聯（替換規則還沒讀）

#### 3-1. 「關於夜讀 → 權限」的權限狀態卡片，最後兩列沒有列首圖示

**會發生什麼**：權限狀態那張卡片上面每一列權限都有列首圖示，下面的「開啟系統設定」「重新整理」兩列沒有，字往左縮、和上面的列對不齊。規格是同一張卡片有一列帶列首圖示，其他列也帶（`docs/design/components.md`「分組清單」的「圖示跟著同一張卡片」，強調色的動作用強調色的同大小線條圖示）。#489 補這條規則時漏了這一頁。

**為什麼**：`lib/features/about/privacy_pages.dart:192-196` 每一列權限給 `leading: SizedBox(width: AppGrouped.iconTile, child: Icon(...))`；同一張卡片的 `:177` 「開啟系統設定」與 `:183` 「重新整理」兩列沒有 `leading`。

**怎麼確認**：在 `test/features/about/` 打開權限頁、等狀態查完，斷言「權限狀態」卡片裡每一列 `GroupedRow` 都有 `leading`。

**修法方向**：兩列各給一個同大小的線條圖示（強調色），照權限列包在 `AppGrouped.iconTile` 寬的方塊裡。

**輕重**：畫面錯。

## 拿不準

- **備份與同步：備份或還原進行中，清單下方是一個置中轉圈**（`lib/features/settings/backup_sync_page.dart:180`）。`DESIGN.md` 原則 4 說不放置中轉圈，但那條講的是載入；這是一件操作的進度，規格沒寫該用什麼，卡在「算不算違反規格」。
- **外部匯入的提示框標題是「外部匯入」**（`lib/features/association/handlers/association_dialog_helper.dart:82`，「無法辨識」同理）。`docs/design/components.md`「提示框」要求標題直接問要做什麼（「匯入這個書源？」），說明只寫一句後果；這裡說明是三段。是規格不符還是用詞意見，沒有把握。
- **介面 3 的 `lib/features/replace_rule/` 5 個檔還沒讀**（`replace_rule_deadline.dart`、`replace_rule_preview.dart`、`widgets/` 3 個）。
