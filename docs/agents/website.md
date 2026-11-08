# 網站與 README 的畫面與短片

網站（`website/`）與 README 的規格在 `docs/design/website.md`。畫面與短片都從 App 真的畫面拍，不手做。

要參考捲動換畫面的版型（手機黏住）時看 `docs/prototypes/website-b/`，不發布的原型。

## 重拍

1. `flutter test --run-skipped -t screens test/screens/website_shots_test.dart -r expanded 2>&1 | grep -v "available)$"`：拍檔裡 `_shots` 列的每一張與每一段短片（全部約 3 分鐘）。只拍幾個用 `SHOT_ONLY=名稱,名稱`。圖寫在系統暫存的 `night-reader-screens/web/`，短片的每一格寫在 `night-reader-screens/web-clips/<名稱>/`。
2. `python -I tool/website_preview/shots.py [名稱…]`：圖縮成寬 786（平板 1000）的 webp 放 `website/shots/`；短片用 ffmpeg 轉成 30 fps 的 mp4 放 `website/clips/`，最後一格另存成 `website/shots/<名稱>.webp` 當封面。要有 ffmpeg 與 Pillow。
3. 每張圖、每段短片的頭中尾都打開看過再提交。
4. README 的卡片跟著重拍：`python -I tool/readme_art/render.py [卡片名稱…]`（Windows，要有 Chrome、ffmpeg、Pillow 與 numpy），拍成 `docs/readme/*.webp`。卡片的字與用哪張畫面在 `tool/readme_art/cards.js`，版面在 `card.html`；改了網站的字也要改這裡。會動的卡片把好幾支手機的畫面疊在同一條 6 秒的時間軸上，抽頭、中、尾幾幀看過再提交。

手機照 393×760、3 倍拍（網站上的手機框同比例）；平板 800×1280、2 倍。正文照網站的排版（`_webTypography`：字大、兩側留白、行距寬），不是 App 的預設。

## 測試環境畫不出來的東西

- **沒指定字型的字畫成方塊**：選字選單、「已隱藏」這類底部提示的字沒有指定字型，手機上是系統字型，測試裡是方塊字，註冊字型也蓋不掉。所以選字隱藏用前後兩張，不錄短片；要拍的畫面裡有這些字時，等它收起來再拍。
- **手勢一放開選取就消失**：App 只處理長按開始，測試的手勢放開時選取會被清掉。要按選字選單時，手指按著就點，之後用 `gesture.cancel()`，放開會被當成點一下正文、叫出閱讀選單。
- **連不上網路**：換源面板自己搜的每個書源都會失敗、清掉結果，要等它搜完再把結果放進面板的 provider（`_fillChangeSource`）。
- **沒有系統狀態列**：「藏起狀態列」拍不出對照，只放藏起來那張。
- **第一次開書要真的排版**：骨架會停很久（手機上快得多），錄開書的短片前先開一次再返回。
- **閱讀位置會被前一段記住**：改正文的情境（`_saveChapter`）會把進度重設到那一章開頭，長按的座標才對得上。
