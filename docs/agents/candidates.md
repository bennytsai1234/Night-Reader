# 畫候選圖給使用者選

`AGENTS.md`「視覺由使用者在圖上選」的細節：App 畫得出來的用 `test/support/screenshot.dart`，系統畫的用 HTML 模擬，幾張圖要比較時做成一頁並排放進對話。

## App 畫得出來的畫面

- 原型寫在 `test/_screens/`（git 忽略），選定後移到資源回收筒。這個資料夾在本機 `flutter analyze` 看得到，留著的話未用到的類別會讓推送前的檢查出警告。
- 要畫在真畫面上（例如浮在書架上的元件）：先用 `test/screens/app_screens_test.dart` 拍真畫面（`SHOT_ONLY=s01`，淺色、深色各跑一次），再在原型測試裡把那張 PNG 當底圖（`runAsync` 裡 `instantiateImageCodec`、`RawImage`），只把候選元件疊上去。
- 候選照 App 的預設畫，使用者平常看到的就是這樣：淺色牛皮、深色素色加純黑、玻璃實色（預設值在 `ThemeSettingsProvider`）。拍整個 App 時，截圖環境的玻璃是霧面，偏好設定蓋上 `PreferKey.glassStrength: 'solid'`；只畫元件的原型自己建主題，淺色 `buildAppTheme(AppStyle.kraft, Brightness.light, glassStrength: GlassStrength.solid)`，深色 `buildAppTheme(AppStyle.plain, Brightness.dark, pureBlack: true, glassStrength: GlassStrength.solid)`。
- 截圖環境畫得出彈出選單、提示框與長按預覽背後的模糊；分頁列、頁首與閱讀選單的模糊（共用背景取樣）沒有驗證過，不拿截圖判斷。
- 某些陰影畫不出來：`BoxShadow` 的大範圍模糊會畫成一塊灰色長條，候選裡的陰影用小的（模糊 6、位移 2）；分不分得開看取樣的明度差，不看圖上的陰影。

## 系統畫的畫面

通知欄播放器、鎖定畫面、動態島、桌面小工具這類由系統照 App 給的資料畫的畫面，Flutter 截圖畫不出來，改用 HTML 模擬。

- 只讓使用者選 App 決定得了的部分：文字、圖片、按鈕的組合；外觀各家不同，在頁面上寫明「樣子由系統決定」。
- Android 通知欄淺色、深色各畫一張，iPhone 鎖定畫面一張。
- 圖片（例如封面）先從截圖裁下來（Python `-I` 跑 PIL），頁面裡用本機絕對路徑的 `<img src>`，`html_preview` 與 `html_render` 會把它內嵌。CSS 裡的 `url()` 與 JS 字串裡的路徑不會內嵌：放一個隱藏的 `<img id>`，用頁面裡的 script 讀它的 `src` 再重複使用，同時讓幾個候選共用一份版型。

## 並排比較

幾個候選差在小地方（例如清單右邊一欄）時，裁出有差的那一塊、放大成兩倍解析度，淺色與深色左右並排，一個候選一列，用 `html_render` 放進對話；整張截圖貼在訊息裡時差異太小看不出來。

## 量間距

要量畫面上的空白（頁首到第一項、卡片裡上下、組與組之間）時，先拍截圖，再用 `python -I tool/spacing_bands.py <截圖>...` 印出每一段的上下緣與段間空白，數字是邏輯像素。量到的是筆畫，差 1～4 的多半是字型留白，先對照元件的內距再下結論。捲到底要重複跳到底、等長度不再變再拍：捲到才建的清單跳一次常常還沒到底。
