window.CARDS = {
  "hero": {"type": "hero", "back": "reader-paper_dark", "front": "launch", "a": "clip:launch:hold"},

  "vol1": {"type": "vol", "t": 0.35, "dim": 0.5, "no": "卷一", "name": "燈下", "w": 196, "items": [
    {"s": "open", "a": "clip:open", "h": "每一幀都準時", "p": "開 App、開書、換頁<br>畫面一路順到底"},
    {"s": "reader-kraft_light", "a": "seq:reader-kraft_light,reader-bamboo_light,reader-tea_dark,reader-plain_dark", "h": "白天一種，晚上一種", "p": "六種風格，白天晚上各挑一個<br>晚上可以純黑"},
    {"s": "tts", "a": "clip:tts", "h": "閉上眼睛聽", "p": "讀到哪句標到哪句<br>可以定時停"}
  ]},
  "vol2": {"type": "vol", "t": 0.6, "dim": 0.5, "no": "卷二", "name": "留白", "w": 168, "gap": 22, "items": [
    {"s": "hide-before", "a": "seq:hide-before,hide-after", "h": "廣告，選起來藏掉", "p": "長按選字按「隱藏」<br>每本書都不再出現"},
    {"s": "clean-before", "a": "seq:clean-before,clean-after", "h": "正文自己整理", "p": "替換規則清掉雜訊<br>簡體一律轉成繁體"},
    {"s": "statusbar-hidden", "h": "只留下字", "p": "藏起狀態列<br>整個螢幕都是正文"},
    {"s": "covers-source", "a": "seq:covers-source,covers-unified", "h": "書架一個樣子", "p": "統一封面<br>不用五花八門的圖"}
  ]},
  "vol3": {"type": "vol", "t": 0.85, "dim": 0.5, "no": "卷三", "name": "枕邊", "w": 134, "gap": 18, "items": [
    {"s": "search", "a": "clip:search", "h": "一次搜遍書源", "p": "繁簡一起找<br>同一本書合成一筆"},
    {"s": "source-change", "h": "換源不迷路", "p": "換了書源還在同一章<br>書籤標註跟著走"},
    {"s": "download", "a": "clip:download", "h": "整本先下載好", "p": "放上書架就整本下載<br>沒網路照樣讀"},
    {"s": "local-toc", "h": "本地書也能讀", "p": "TXT、EPUB<br>匯入就自動分章"},
    {"s": "sync-phone", "h": "換一台接著讀", "p": "Google 雲端硬碟<br>或 WebDAV"}
  ]},
  "vol4": {"type": "vol", "t": 1, "dim": 0.55, "no": "卷四", "name": "尋源", "w": 196, "moon": [430, -170], "items": [
    {"s": "source-check", "h": "書源壞了一眼看出", "p": "批次校驗找出失效的<br>單一書源逐步除錯"}
  ], "note": ["夜讀不附書源", "網路上搜「Legado 書源」，在書源網站點「一鍵導入」就會打開夜讀"]},

  "download": {"type": "download"}
}
