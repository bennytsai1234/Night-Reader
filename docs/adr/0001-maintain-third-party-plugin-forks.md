# 自行維護 flutter_tts、flutter_js、file_picker、xpath_selector 四個 fork

2026-09-18（`1cf0d5d`）起，`flutter_tts` 4.2.5、`flutter_js` 0.8.7、`file_picker` 11.0.3 以 path dependency 放在 `third_party/`，因為上游發布的版本用的是 AGP 9 已移除的 `kotlin-android`、`kotlinOptions`、`lintOptions`（`file_picker` 另需 Win32 6），等不到上游修。2026-10-09 起（`5eea100`、`ed43080`）改為完全自行維護、不再追上游：只保留 Android 實作，視同專案程式碼，跑同一套 `dart format` 與 `flutter analyze`。2026-10-14 為了提供 iOS 版（ADR 0003），從刪除前的版本補回三者的 iOS 實作與 `flutter_js` 的 JavaScriptCore 執行環境。2026-11-02 起 `xpath_selector` 3.0.2 也放進 `third_party/`（#214、#217），理由不同：上游不支援 Legado（JsoupXpath）書源用到的 XPath 寫法（只寫子元素或屬性名稱的存在條件、從目前那一項往下找的相對路徑、引號裡的 `|`），只改這幾處；它是純 Dart，沒有平台實作，`xpath_selector_html_parser` 用 `dependency_overrides` 換成同一份。各套件的來源封存檔雜湊與修補內容記在各自的 `PATCHES.md`。

## Consequences

- 升級這四個套件要手動比對上游並更新 `PATCHES.md`，`flutter pub upgrade` 不會動到它們。
- 三個平台外掛只有 Android 與 iOS 實作，其他平台的建置不可能成功（見 ADR 0003）。
- `flutter_js` 的桌面測試靠 `test/fixtures/quickjs/` 裡的 QuickJS 橋接函式庫；缺檔時測試直接失敗，不會跳過。
