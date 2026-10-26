---
name: animation-dashboard
description: 動畫儀表板：把一段動畫逐格錄下來，做成可以播放、逐格點選的頁面放進對話，向使用者說明動畫的時間軸、每段在做什麼、主執行緒在哪一格超過 8ms。說明或比較動畫、轉場、骨架、進場的流程與候選，或回報動畫改前改後時使用。
---

# 動畫儀表板

使用者看儀表板判斷動畫的問題在哪；動畫實際好不好看，使用者在手機上看。頁面的版型就是 `tool/frame_viewer/template.html`：上面幾支手機同步逐格播放（含「目前」當對照），下面是分段色條、每格的畫面變化、指定位置的深淺、每格主執行緒花的時間，點圖跳到那一格，點手機換成那一支的資料。

## 步驟

1. **錄影**：在 `test/_screens/`（git 忽略）寫一個臨時測試，用 `test/support/frame_recording.dart` 的 `recordAnimation` 錄；寫法、檔名規則與量測的限制在那個檔的檔頭。每個候選（含目前）× 每個變化 × 淺色、深色各錄一段；整個 App 的動畫先開一次暖身再錄。`phase()` 回傳的段落名稱要和下一步設定檔 `phases` 的鍵一模一樣。測試放背景跑（`flutter test test/_screens/<檔名>_test.dart`，一般一兩分鐘）。
   完成：`%TEMP%\night-reader-frames\` 下每一段都有 `frames.rgba` 與 `meta.json`，從 `meta.json` 的 `phases` 列出每段的起訖格核對過：開頭有動畫開始前的那段，結尾錄到動畫播完後的靜止畫面（`until` 成立時動畫可能還在播，`tailFrames` 要蓋過剩下的時長），每段的格數和程式裡的時長對得上（一格 16ms）。

2. **設定檔**：寫在 repo 外（例如 `%TEMP%\night-reader-frames\<主題>.json`），照 `tool/frame_viewer/example.json`（開 App 進場的實例）改；每個欄位的意思在 `tool/frame_viewer/build.py` 的檔頭。每一段都寫說明（`notes`），用使用者的詞講這段畫面在做什麼、主執行緒在忙什麼；這是頁面上讓使用者讀懂時間軸的地方。
   完成：每個錄到的段落名稱都有對應的 `phases` 鍵與說明。

3. **做頁面**：`python tool/frame_viewer/build.py <設定檔>`，輸出 `viewer/page.html`。把 `page.html` 的內容整份交給 `html_preview`：主控台沒有錯誤、拼圖逐格對得上、色條分段和說明對得上；再用它回報的高度交給 `html_render`。
   完成：儀表板已經放在對話裡。

   判讀「畫面變化」的尖刺前先看差多少：錄影把畫面縮成邏輯尺寸，定格換場這類貼圖（用裝置像素比拍）和直接畫的文字縮小後邊緣不一樣，換上圖、換回真畫面的那一格會有一片文字邊緣在變；手機上沒有這一步縮小，不算收尾跳變。

4. **回覆**：頁面已經畫出的不再重述，只補頁面說不出的：尖峰在哪一段、為什麼、你的判斷與建議。改前改後的比較加一張表：每段最忙的一格（以 8ms 為線）、開 App 到結束的時間。

5. **收尾**：刪掉自己這次在 `%TEMP%\night-reader-frames\` 的錄影與 `viewer/`，以及 `test/_screens/` 裡這次的臨時測試。
