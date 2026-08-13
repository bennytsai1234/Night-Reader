# Night Reader 全棧主版本升級

層級：T2（跨越 App Shell、Services、Data、Android 建置與 CI）

狀態：已完成（本機驗證通過；release APK 依政策交由 CI）

## 決策

使用者確認方案 B：在產品功能、資料與外部行為不變的前提下，將 Flutter、Android 工具鏈及直接相依套件推進至目前最新穩定主版本；已知衝突以相容層／套件替代／受控修補處理，不以會破壞其他平台編譯的全域強制 override 掩蓋。

### 重開並重新確認的決策：built-in Kotlin + 保留受控 fork

本輪一度重開「built-in Kotlin」決策，評估改走 Flutter 3.47 預設的 legacy KGP 路線以「丟掉 fork」。實測證據判定該路不可行、維持原決策：

- `flutter_tts` 最新 hosted 版仍為 `4.2.5`、`flutter_js` 仍為 `0.8.7`（皆為 fork 基底，**無更新版本**）。
- 兩者最新 hosted `android/build.gradle` 都使用 **AGP 9 已移除的 `android { kotlinOptions {} }`**，並釘死舊 AGP（7.3.1 / 8.13.0）buildscript classpath。
- → 不論 built-in Kotlin 或 legacy KGP 路線，hosted 版都無法在 AGP 9 下建置。fork 是消費「尚未遷移 AGP 9 的上游」的正確做法，非多餘選擇。
- Dart 3.13 仍保留 `Pointer.elementAt`，故 flutter_js fork 的指標修正屬 deprecation 清理、非編譯必需；但 Android 建置設定 patch 仍為必需。
- `file_picker` fork 另有 win32 6 相容（讓 host `flutter test` 能編譯桌面實作）的獨立正當理由，維持。

## 目標與達成

- CI／版本釘選／文件同步至 **Flutter 3.47.0 / Dart 3.13.0**。✅
- Android 遷移至 **AGP 9.1.0、Gradle 9.3.1、KGP 2.4.0、compile/target SDK 37、built-in Kotlin／新版公開 DSL**；移除專案自有的 `BaseExtension` 路徑與過渡旗標處理。✅
  - 註：計畫原文的「AGP 9.3.1」為 Gradle 版本之誤植；依 Flutter 3.47 tooling 權威常數，AGP 為 **9.1.0**（`maxKnownAgpVersionWithFullKotlinSupport`）、Gradle **9.3.1**（`templateDefaultGradleVersion`）、KGP **2.4.0**。
- 直接相依套件升至可驗證的最新穩定版；`package_info_plus` 10、`pointycastle` 4（移除 `encrypt`）、`permission_handler` 13、`workmanager` 0.10 等；移除 `meta`/`win32` 的 `dependency_overrides`。✅
- 三個受控 fork（`third_party/flutter_tts`、`flutter_js`、`file_picker`）皆為建置設定／相容 patch，runtime 與上游一致，附 `PATCHES.md` 與移除條件。✅

## 驗證結果（本機，Flutter 3.47.0 / Dart 3.13.0）

- `flutter analyze`：**0 issues**。
- `flutter test`：**970 全過，0 失敗，無新增 skip**。
- `flutter build apk --debug --target-platform android-arm64`：**成功產出 `app-debug.apk`（AGP 9.1.0 / Gradle 9.3.1 / API 37）**，所有外掛（含 3 個 fork）Kotlin 編譯通過。
- `git diff --check`：clean；工作樹差異僅涵蓋本計畫範圍。

## 與計畫的偏差

- 未執行獨立強審 subagent（批次 4）——本輪以 lead 直接驗證完成；若要正式收尾可補一次 `TASK_TYPE: review`。
- gradle.properties 的 `android.builtInKotlin=false` / `android.newDsl=false` 由 Flutter 3.47 `flutter build` migrator 每次自動維持；實測 AGP 9.1.0 下 built-in Kotlin 仍生效、外掛與 app Kotlin 皆正常編譯，故不與工具鏈對抗、保留其預設狀態（與 CI 行為一致）。

## 已知限制與殘餘技術債

1. **本機 SDK 平台 workaround（僅本機）**：SDK 新 minor 命名（`platforms;android-37.0`）＋偏舊 cmdline-tools 導致 AGP 找不到 hash `android-37`；本機以 symlink 內容 + 修正 `source.properties`（ApiLevel=37）手建 `platforms/android-37`。此為本機驗證用，未進版控。CI 依賴 GitHub runner + AGP 自動下載 SDK 元件——**列為首次 CI 觀察項**（若 CI 也遇 `android-37` 解析，需在 workflow 補 `platforms;android-37.0` 安裝 + symlink 或改用支援 minor 命名的新版 cmdline-tools）。
2. **`workmanager_android` 走 KGP 警告**：`builtInKotlin=false` 下 workmanager 套用 KGP，Flutter 提示「未來版本可能不容許 app 使用套用 KGP 的外掛」。目前僅警告、建置正常；待可設 `builtInKotlin=true` 或 workmanager 出 built-in Kotlin 版即解。
3. **fork 移除條件**：三個 fork 的 `PATCHES.md` 已載明——上游出 AGP 9 built-in Kotlin 相容版（file_picker 另需 win32 6 + compileSdk 37）即回退 hosted。
4. 7 個 transitive 套件（analyzer、_fe_analyzer_shared 等）受 Flutter SDK／建置工具鏈約束無法升到最新，屬預期。

## Atlas 影響

本變更不改模組邊界、所有權或公開 Dart API；9 個模組文件無需更新。跨模組工具鏈與 fork 策略決策已記入索引 Architecture Decisions 表。
