# 交接（2026-11-24）

## 你要的
- 換對話的原因：使用者的額度快用完，要求現在停手交接。
- 原本的交辦整段在這個對話的第一則訊息（「規劃未來藍圖」對話開出來的全面檢查：讀書源 0、1、2，問題寫進 `docs/proposals/audit-source-engine.md`，只讀只列不修）。使用者原話：「巡檢關閉，改用手動全面檢查」「Claude 讀」。

## 做到哪
- 清單檔已推上 `beta`（最後一次是 `2ac5a8f1`）：書源 0（規則 JS）找到 4 筆、書源 1（規則解析）找到 4 筆，拿不準 9 筆；每筆都查過舊 issue 與 PR、對過 Legado。
- 讀的 SHA 是 `fff55f9c`，進度表照實寫；書源 2 還沒讀。
- 書源 1 裡 `css/analyze_by_css_support.dart` 的選擇器相容層只略讀，進度表已註明。

## 還沒定、這個對話自己判斷的
- 「拿不準」那幾筆是這個對話判斷證據不夠才沒列成問題，使用者沒看過。
- Big5 那筆（第 8 筆）的解碼一半在 `lib/core/utils/encoding_detect.dart`，屬於書源 2 的檔，先寫在書源 1。

## 下一步
- 先載入 `handoff` 和 `writing-for-agents`，把理解講給使用者聽，使用者說可以再動手。
- 接著讀書源 2：`lib/core/engine/web_book/`、`source_isolate/`、`lib/core/network/`（`cookie_store`、`backstage_webview`、`webview_cloudflare_solver`、`webview_data_service` 不讀）、`lib/core/utils/` 的 `network_utils`、`idna`、`public_suffix`、`encoding_detect`；讀完照第一則訊息存檔、推 `beta`，再用 `t3_thread_send` 回報給 threadId `bd7398c0-6b9b-498e-93bd-c0efa754ebd2`。
