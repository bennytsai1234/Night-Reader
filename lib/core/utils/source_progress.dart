import 'dart:async';

/// 書源工作一邊跑一邊交回的紀錄：交給呼叫端在 `SourceIsolate.run`、
/// `SourceWorker.run` 給的 `onProgress`。工作在書源 isolate 裡時每一筆當下
/// 就送回呼叫端的 isolate，不等工作返回：規則 JS 同步等網路時工作停住，
/// 外層先結束也拿得到已經走到的紀錄；工作失敗時也不會丟。
///
/// 每一筆要送得過 isolate（只帶資料的物件）。沒有人收時什麼都不做。
void reportSourceProgress(Object entry) => currentSourceProgress?.call(entry);

/// 這個 Zone 裡的紀錄交給誰；沒有人收是 null。在某段工作開始時記下它，之後
/// 的紀錄交給記下的那個（[RequestLog] 就是這樣），裡面又包一層收紀錄的也
/// 不會被搶走。
void Function(Object entry)? get currentSourceProgress =>
    Zone.current[sourceProgressZoneKey] as void Function(Object entry)?;

/// 收紀錄的人放在 Zone 的這個鍵；只給 `SourceIsolate` 用。
final Object sourceProgressZoneKey = Object();

/// 引擎寫給書源除錯看的一句話，例如書單是空的、改照詳情頁解析（照 Legado
/// 的 `Debug.log`）。書源除錯照順序寫進紀錄；其他時候沒有人收。
final class SourceDebugNote {
  const SourceDebugNote(this.message);

  final String message;
}
