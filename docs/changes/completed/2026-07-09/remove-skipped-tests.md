# Remove Skipped Tests

## Context

`flutter test` passes with 678 successful tests and 4 skipped tests.

Skipped tests:

- `test/core/engine/engine_integration_test.dart`
  - `ContentParser replaceRegex cleans content`
  - `ContentParser replaceRegex with empty replacement (deletion)`
- `test/core/engine/reference_logic_test.dart`
  - `JS 依賴場景 JsonPath + java.put() 邊際行為`
  - `JS 依賴場景 {{ }} 模板 JS 求值`

## Plan

- Update the `replaceRegex` tests to use current whole-content replacement syntax: `##regex##replacement`.
- Keep the behavior checks active by removing the `skip:` metadata.
- Remove the two empty JS placeholder tests because they do not assert behavior.

## Verification

- Passed: `flutter test test/core/engine/engine_integration_test.dart test/core/engine/reference_logic_test.dart`
- Passed: `flutter test` (680 passed / 0 skipped)
- Passed: `flutter analyze`

## Notes

- Multi-step whole-content `replaceRegex` chaining remains a behavior gap to clarify separately; these tests now cover one non-empty replacement and one empty-replacement deletion using current syntax.
