# 滑動視窗提前擴張門檻：一律用最大提前量

## Before

- `ScrollReaderV2ViewportModel.shiftThreshold()`（`viewport/scroll_reader_v2_viewport_model.dart:78-85`）依 `scrollVelocity` 決定「捲到離視窗邊界多遠就要提前擴張視窗/排版下一段內容」：速度愈快提前量愈大（最多 1.5 個螢幕高），速度愈慢退回最小值（120px 或 20% 螢幕高）。
- `ScrollReaderV2MotionController.scrollVelocity`（`viewport/scroll_reader_v2_motion_controller.dart:99-100`）在手指拖曳中恆為 `0`（`scrollAnimation` 只有放手後的甩動 fling 才在跑），甩動減速尾聲也會跟著瞬時速度即時收斂。結果：拖曳中（不論快慢）與甩動減速尾聲都只有最小提前量，視窗擴張是「臨時反應」，容易撞上同步排版造成卡頓；只有放手瞬間的高速甩動才吃得到大提前量。

## After

- 改為一律使用原本速度公式能算出的最大提前量（`viewportHeight() * 1.5`），不論拖曳/甩動/靜止都不再依速度縮小門檻。用記憶體/CPU 換取滑動時不再因臨時排版而卡頓，取代原本評估過但更複雜的「拖曳追蹤真實速度 + 甩動峰值緩降衰減」方案（使用者選擇直接一律拉滿，不要精細調校）。
- `scrollVelocity` 參數保留在函式簽章（呼叫端不用改），只是目前未使用。

## 驗證結果

- `flutter analyze`：全專案 0 issue。
- `flutter test`：613 全過，0 失敗。
- 本機無 Android SDK，無法實測真機手感；若之後發現記憶體/CPU 負擔明顯，可以再依 Known Risk「過度預載會吃記憶」評估收斂。
