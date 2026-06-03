# fix: 修正 dispose() 中備用存檔的 race condition

## 任務類型
Bug

## 確認的之前
`ReaderV2ControllerHost.dispose()` 呼叫 `unawaited(runtime?.flushProgress())`，
下一行就 `runtime?.dispose()` 設置 `_disposed = true` 並 dispose `_progressController`。
`_saveProgressLocation` 在 async 執行時通過 `_disposed` check（此時仍 false），
但 suspend 在 `await _progressController.saveImmediately()` 時，
`_progressController` 已被 dispose，造成 race condition。
正常退出路徑（exit coordinator）在 `popNavigator()` 前已正確 `await persistExitProgress()`，
這個 safety net 是失效的死代碼。

## 確認的之後
移除 `unawaited(runtime?.flushProgress())` 那行。
`dispose()` 只清理資源，退出存檔由 exit coordinator 負責。
版本升至 0.2.101+115。

## 預期的檔案範圍
- `lib/features/reader_v2/application/reader_v2_controller_host.dart`
- `pubspec.yaml`

## 驗證步驟
- `flutter analyze`
- `flutter test test/features/reader_v2/`

## 回退路徑
git revert 兩個檔案的修改；因為 safety net 本來就無效，回退無實際行為影響。
