# 自行維護 flutter_tts、flutter_js、file_picker 三個 fork

2026-09-18（`1cf0d5d`）起，`flutter_tts` 4.2.5、`flutter_js` 0.8.7、`file_picker` 11.0.3 以 path dependency 放在 `third_party/`，因為上游發布的版本用的是 AGP 9 已移除的 `kotlin-android`、`kotlinOptions`、`lintOptions`（`file_picker` 另需 Win32 6），等不到上游修。2026-10-09 起（`5eea100`、`ed43080`）改為完全自行維護、不再追上游：只保留 Android 實作，視同專案程式碼，跑同一套 `dart format` 與 `flutter analyze`。各套件的來源封存檔雜湊與修補內容記在各自的 `PATCHES.md`。

## Consequences

- 升級這三個套件要手動比對上游並更新 `PATCHES.md`，`flutter pub upgrade` 不會動到它們。
- 只剩 Android 實作，其他平台的建置不可能成功（見 ADR 0003）。
- `flutter_js` 的桌面測試靠 `test/fixtures/quickjs/` 裡的 QuickJS 橋接函式庫；缺檔時測試直接失敗，不會跳過。
