window.CARDS = {
  "hero": {"type": "hero", "back": "reader-paper_dark", "front": "launch", "a": "clip:launch:hold"},

  "reading": {"type": "row", "t": 0.35, "dim": 0.5, "w": 196, "items": [
    {"s": "open", "a": "clip:open", "h": "流暢", "p": "開 App、開書、換頁<br>都不掉幀"},
    {"s": "reader-kraft_light", "a": "wipe:reader-kraft_light,reader-bamboo_light,reader-tea_dark,reader-plain_dark", "h": "六種風格", "p": "白天、晚上各選一個<br>晚上可以純黑"},
    {"s": "tts", "a": "clip:tts", "h": "朗讀", "p": "標出正在讀的那句<br>可以定時停"}
  ]},
  "tidy": {"type": "row", "t": 0.6, "dim": 0.5, "w": 168, "gap": 22, "items": [
    {"s": "hide-before", "a": "fade:hide-before,hide-after", "h": "隱藏廣告", "p": "長按選字按「隱藏」<br>每本書都不再出現"},
    {"s": "clean-before", "a": "fade:clean-before,clean-after", "h": "正文整理", "p": "替換規則清掉雜訊<br>簡體轉成繁體"},
    {"s": "statusbar-hidden", "h": "隱藏狀態列", "p": "整個螢幕都是正文"},
    {"s": "covers-source", "a": "wipe:covers-source,covers-unified", "h": "統一封面", "p": "書架上的書<br>不用書源的封面"}
  ]},
  "library": {"type": "row", "t": 0.85, "dim": 0.5, "w": 134, "gap": 18, "items": [
    {"s": "search", "a": "clip:search", "h": "多書源搜尋", "p": "繁簡一起找<br>同一本書合成一筆"},
    {"s": "source-change", "h": "換源", "p": "停在同一章<br>書籤和標註都還在"},
    {"s": "download", "a": "clip:download", "h": "整本下載", "p": "放上書架就整本下載<br>沒網路也能讀"},
    {"s": "local-toc", "h": "本地書", "p": "TXT、EPUB<br>匯入自動分章"},
    {"s": "sync-phone", "a": "devices:sync-phone,sync-tablet", "h": "多台同步", "p": "Google 雲端硬碟<br>或 WebDAV"}
  ]},
  "sources": {"type": "row", "t": 1, "dim": 0.55, "w": 196, "moon": [430, -170], "items": [
    {"s": "source-check", "h": "書源校驗", "p": "批次找出失效的書源<br>也能逐步除錯"}
  ], "note": ["夜讀不附書源", "網路上搜「Legado 書源」，在書源網站點「一鍵導入」就會打開夜讀"]},

  "download": {"type": "download"}
}
