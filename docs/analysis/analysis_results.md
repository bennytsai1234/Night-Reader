謝謝你的描述，這完全不是像素不對齊。讓我重新定位問題。

## 你遇到的真正問題

**「頓一下、跳一下、文字換位置」= strip 座標在動畫中被改變了。**

以下是發生的事：

```
減速中 → 接近/進入下一章
  → _scheduleWindowShiftForAnchor
    → ensureWindowAround
      → placeWindowInStrip  ← 重算所有章節的世界座標
        → 如果某章正在背景排版、高度變了
          → _reanchorGrownChapter 改變 startY
            → 可見 tile 的 worldTop 跳了幾像素
              → 你看到文字「換位置」
```

具體在 [_reanchorGrownChapter](file:///c:/Users/045650/Desktop/Project/product/Night-Reader/lib/features/reader_v2/viewport/scroll_reader_v2_viewport_model.dart#L415-L438)：

```dart
// 部分就緒的章節長高了 → startY 往上移
if (anchoredToBottom) {
  strip.placeChapter(
    startY: segmentEnd - chapter.extent,  // ← startY 變了！
    height: chapter.extent,
  );
}
```

或是 [placeWindowInStrip](file:///c:/Users/045650/Desktop/Project/product/Night-Reader/lib/features/reader_v2/viewport/scroll_reader_v2_viewport_model.dart#L168-L214) 在視窗中心換章時，用新的 `liveExtent` 重排前後章的座標——如果某章的高度與上次不同，所有鄰接的章都跟著移。

## 為什麼只在減速末段出現

| 階段 | 為什麼看不見 / 看得見 |
|------|------------------|
| 高速 | 每幀移動 40+ px，座標跳 2-3px 被淹沒 |
| 減速末段 | 每幀移動 1-2px，座標跳 2-3px → **整個畫面閃跳一次** |

而且減速末段才是你最可能**跨越章節邊界或接近部分排版章節**的時候。

## 修正方向

問題不在頻率，而在**座標變了但 readingY 沒跟著補償**。標準做法是：

> **strip 座標改變時，同步調整 readingY 相同的偏移量，讓螢幕上的視覺位置不變。**

例如某章的 `startY` 從 5000 變成 4997（高度長了 3px，底部對齊所以頂部往上 3px），則 `readingY -= 3`，螢幕上看到的一切不動。

這才是治本的方向。要我沿著這個思路深入分析可行性嗎？
讓我追蹤觸發跳動的完整路徑。

Viewed scroll_reader_v2_viewport_model.dart:395-440
Viewed scroll_reader_v2_viewport.dart:278-310
Viewed scroll_reader_v2_viewport.dart:165-180

好，完整路徑看完了。以下是分析：

---

## 跳動的兩條觸發路徑

### 路徑 1：背景排版長高 → `_reanchorGrownChapter`

```
背景排版完成一批段落
  → cacheManager 通知 chapter extent 變了
    → _handleChapterCacheUpdated(chapterIndex)
      → _reanchorGrownChapter(chapterIndex)
        → strip.placeChapter(新 startY 或新 height)   ← 座標變了
      → onWindowContentChanged()
        → _scheduleContentProgressRebuild()
          → setState()                                ← 用新座標重繪
                                                      ← readingY 沒動 → 跳！
```

具體分兩種情況：

| 情況 | startY 變化 | 例子 |
|------|-----------|------|
| `anchoredToBottom`（上一章，底部對齊） | **往上移**（`segmentEnd - newExtent`） | 章排完更多段落，高度從 3000 變 3200，startY 從 0 變 -200 |
| 非 anchoredToBottom（下一章，頂部固定） | **不變**，但 height 長了 | 安全，不會跳 |

所以路徑 1 **只在你能看到上方的「部分就緒章節」時才會跳**。

### 路徑 2：視窗中心換章 → `placeWindowInStrip`

```
動畫中 → _scheduleWindowShiftForAnchor
  → _shiftWindowForAnchor：發現 anchor 已在新章
    → _ensureWindowAround(新章)
      → viewportModel.ensureWindowAround
        → cacheManager.ensureWindowAround（async，可能 await）
        → placeWindowInStrip(window)
          → 用 liveExtent 重算所有章座標   ← 座標可能變了
      → setState()                         ← readingY 沒補償 → 跳！
```

`placeWindowInStrip` 用 `liveExtent`（即時高度）而非快照高度，如果某章在 `await` 期間被背景排版改了高度，重放座標就會跟之前不同。

---

## 修復思路：readingY 補償

**原則**：strip 座標改變時，算出「使用者正在看的那個世界座標」移動了多少，同步調整 `readingY` 相同的量。`screenY = worldTop - readingY` 兩邊同時移 → 螢幕上不動。

### 補償點 1：`_reanchorGrownChapter`

```dart
void _handleChapterCacheUpdated(int chapterIndex) {
    // ① 記住使用者正在看的章節的舊 top
    final anchorChapter = /* 目前 readingY 對應的章 */;
    final oldTop = strip.chapterTop(anchorChapter);

    _reanchorGrownChapter(chapterIndex);

    // ② 算 delta
    final newTop = strip.chapterTop(anchorChapter);
    final delta = (oldTop != null && newTop != null) ? newTop - oldTop : 0.0;
    
    // ③ 通知 viewport 補償
    onWindowContentChanged?.call(delta);  // 改簽名，帶 delta
}
```

viewport state 收到 delta 後：
```dart
if (delta != 0) _motion.setReadingY(_motion.readingY + delta);
```

### 補償點 2：`_ensureWindowAround`

```dart
Future<void> _ensureWindowAround(int chapterIndex, ...) async {
    // ① 記住 anchor 章的舊 top
    final anchor = _viewportModel.anchorChapterIndex(_motion.readingY);
    final oldTop = _viewportModel.strip.chapterTop(anchor);

    await _viewportModel.ensureWindowAround(chapterIndex, ...);

    // ② 補償
    final newTop = _viewportModel.strip.chapterTop(anchor);
    if (oldTop != null && newTop != null) {
        _motion.setReadingY(_motion.readingY + (newTop - oldTop));
    }
    ...
}
```

### 複雜度

- **改動檔案**：`scroll_reader_v2_viewport_model.dart` + `scroll_reader_v2_viewport.dart`
- **風險**：中等。如果動畫進行中調 readingY，需同步更新 `scrollAnimation.value`，否則下一 tick 的 delta 算錯
- **需額外處理**：viewport model 目前沒有 `readingY`，需要透過 callback 或注入方式取得 anchor 資訊

你覺得這個方向合理嗎？有什麼疑慮？