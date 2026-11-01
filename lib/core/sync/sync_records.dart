import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 同步的一筆資料：一本書的閱讀進度、一個書源……（ADR 0039）。
class SyncRecord {
  const SyncRecord({
    required this.time,
    required this.data,
    this.deleted = false,
  });

  /// 最後修改時間（毫秒）；兩台都改過同一筆時新的贏。
  final int time;

  /// 這筆要同步的內容；只放兩台手機共通的欄位。
  final Map<String, Object?> data;

  /// 這筆在某一台刪掉了；另一台照著刪，不把它加回來。
  final bool deleted;

  /// 內容的指紋：內容一樣就一樣，和最後修改時間無關。開書沒有翻頁也會更新
  /// 時間，判斷「改過沒有」只看指紋。
  String get fingerprint => deleted
      ? 'deleted'
      : md5.convert(utf8.encode(_canonicalJson(data))).toString();

  Map<String, Object?> toJson() => {
    'time': time,
    if (deleted) 'deleted': true,
    if (!deleted) 'data': data,
  };

  /// 讀雲端的一筆；格式不對傳回 null（略過，不讓一筆壞掉的擋住整份）。
  static SyncRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final time = json['time'];
    if (time is! int) return null;
    if (json['deleted'] == true) {
      return SyncRecord(time: time, data: const {}, deleted: true);
    }
    final data = json['data'];
    if (data is! Map) return null;
    return SyncRecord(time: time, data: Map<String, Object?>.from(data));
  }
}

/// 同步空間裡的一份檔案：一種資料（例如全部的閱讀進度）的所有紀錄。
class SyncDocument {
  const SyncDocument(this.records);

  static const int format = 1;

  final Map<String, SyncRecord> records;

  String encode() => jsonEncode({
    'format': format,
    'records': {
      for (final entry in records.entries) entry.key: entry.value.toJson(),
    },
  });

  /// 讀雲端的檔案。不是夜讀寫的同步檔（不是物件、沒有 records）時丟
  /// [FormatException]，不拿空的當成雲端沒有資料、把整份蓋掉。
  static SyncDocument decode(String content) {
    final json = jsonDecode(content);
    if (json is! Map || json['records'] is! Map) {
      throw const FormatException('不是夜讀的同步檔');
    }
    final records = <String, SyncRecord>{};
    for (final entry in (json['records'] as Map).entries) {
      final record = SyncRecord.fromJson(entry.value);
      if (entry.key is String && record != null) {
        records[entry.key as String] = record;
      }
    }
    return SyncDocument(records);
  }
}

/// 上次同步時一筆的樣子：本機與雲端各自的指紋，與當時雲端那筆的時間。
/// 和這次的比對，才分得出是哪一邊改過（三方比對）。
class SyncBaseEntry {
  const SyncBaseEntry({
    required this.local,
    required this.remote,
    required this.time,
  });

  /// 同步完本機這筆的指紋。套用雲端的進度時章節序號照本機目錄對過，
  /// 可能和雲端的指紋不同。
  final String local;
  final String remote;
  final int time;

  Map<String, Object?> toJson() => {'l': local, 'r': remote, 't': time};

  static SyncBaseEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final local = json['l'];
    final remote = json['r'];
    final time = json['t'];
    if (local is! String || remote is! String || time is! int) return null;
    return SyncBaseEntry(local: local, remote: remote, time: time);
  }
}

/// 一筆合併的結果。
enum SyncDecision {
  /// 兩邊一樣，或都沒改。
  same,

  /// 本機的較新，寫到雲端。
  upload,

  /// 雲端的較新，套用到這台。
  apply,
}

/// 比對一筆：[local] 本機、[remote] 雲端、[base] 上次同步時。
///
/// - 只有一邊改過（指紋和上次同步時不同）就用那一邊的。
/// - 兩邊都改過，或從沒同步過、內容不同，最後修改時間新的贏。
/// - 雲端和上次不同、時間卻不比上次新：別台同時寫入、蓋掉了這台寫上去的。
///   本機有就再寫一次，被蓋掉的改動只晚一次到。
SyncDecision decideSync({
  required SyncRecord? local,
  required SyncRecord? remote,
  required SyncBaseEntry? base,
}) {
  if (local == null && remote == null) return SyncDecision.same;
  if (remote == null) return SyncDecision.upload;
  if (local == null) {
    return base != null && remote.fingerprint == base.remote
        ? SyncDecision.same
        : SyncDecision.apply;
  }
  final localPrint = local.fingerprint;
  final remotePrint = remote.fingerprint;
  if (localPrint == remotePrint) return SyncDecision.same;
  if (base == null) {
    return local.time >= remote.time ? SyncDecision.upload : SyncDecision.apply;
  }
  final localChanged = localPrint != base.local;
  final remoteDiffers = remotePrint != base.remote;
  if (remoteDiffers && remote.time <= base.time) return SyncDecision.upload;
  if (!remoteDiffers) {
    return localChanged ? SyncDecision.upload : SyncDecision.same;
  }
  if (!localChanged) return SyncDecision.apply;
  return local.time >= remote.time ? SyncDecision.upload : SyncDecision.apply;
}

/// 同一個內容固定寫成同一串字（物件的鍵照字母排），指紋才穩定。
String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}
