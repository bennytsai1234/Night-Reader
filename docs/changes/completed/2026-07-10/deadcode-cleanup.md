# Dead code cleanup

## Before

`lib/core/constant/page_anim.dart`、`lib/core/models/book/book_content.dart`、`lib/core/utils/logger.dart` 與 `lib/core/utils/string_extensions.dart` 沒有被正式入口或任何 Dart import/export 引用；其宣告也沒有在 repo 內被使用。它們是掃描確認的高信心 legacy dead code。

## After

移除上述 4 個未使用檔案，保留 association、測試專用模型、隱私頁與 Reader V2 預留元件。以 `flutter analyze` 與 `flutter test` 驗證刪除不影響現有程式與測試。

## Scope

- 不修改功能邏輯、不調整外部依賴。
- 不刪除只有測試引用的檔案。
- 不刪除文件仍描述為產品模組、但目前未接線的 association 與 Reader V2 元件。

## Verification

- `flutter analyze`：通過，無問題。
- `flutter test`：通過，694 項測試全部通過。
