# 2026-08-13

- 完成全棧主版本升級（T2）：Flutter 3.47 / Dart 3.13、Android AGP 9.1.0 / Gradle 9.3.1 / KGP 2.4.0 / API 37 / built-in Kotlin，直接相依全面升級，三個受控 fork（flutter_tts / flutter_js / file_picker）以建置設定 patch 支援 AGP 9。重開並重新確認「built-in Kotlin + 保留 fork」決策（實測上游無 AGP 9 相容版，無法丟 fork）。本機驗證：`flutter analyze` 0 issues、`flutter test` 970 全過、`flutter build apk --debug` 成功；release APK 依政策交 CI。Atlas 模組文件無需更新，跨模組決策記入索引 Architecture Decisions。
