import 'dart:convert';

import 'package:night_reader/core/database/app_database.dart' show ReadDay;
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/read_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_base_storage.dart';
import 'sync_kind.dart';
import 'sync_records.dart';
import 'sync_settings.dart';

/// 閱讀統計的同步：各台分開記，一台一筆，只有那一台自己寫；閱讀統計頁
/// 顯示這台的加上別台的（ADR 0039）。兩台同時讀也不會互相蓋掉秒數。
///
/// 還原了另一台的備份時，那台的累計已經在這台的統計裡、也在雲端那台的
/// 那筆裡：還原進來的部分（[RestoredStats]）這台不送上去，雲端有那台的
/// 那筆時畫面上也不再加一次。
class ReadStatsSync extends SyncKind {
  ReadStatsSync({
    required this._settings,
    required this._bases,
    ReadRecordDao? dao,
    SharedPreferences? prefs,
  }) : _dao = dao ?? getIt<ReadRecordDao>(),
       _prefs = prefs ?? getIt<SharedPreferences>();

  final SyncSettings _settings;
  final SyncBaseStorage _bases;
  final ReadRecordDao _dao;
  final SharedPreferences _prefs;

  /// 別台的統計存在這台的檔名，和上次同步的紀錄放在一起，換同步空間時
  /// 一起清掉。
  static const String othersFile = 'read_stats_others';

  /// 這台的 id；[local] 讀過才有。
  String? _deviceId;

  @override
  String get name => 'read_stats';

  /// 別台換掉或重裝後，舊的那筆留在雲端照樣加總，那些時間確實讀過。
  @override
  bool get syncsDeletion => false;

  /// 這台那筆只有這台寫，這台的永遠比較新：不套「從沒同步過時雲端的贏」，
  /// 停用後再打開（上次同步的紀錄清掉了）也照樣送上去。
  @override
  bool get hasOwnTime => true;

  @override
  Future<Map<String, SyncRecord>> local() async {
    final deviceId = _deviceId ??= await _settings.deviceId();
    final restored = RestoredStats.read(_prefs);
    final skip = restored != null && restored.from != deviceId
        ? restored
        : RestoredStats.none;
    final days = <String, int>{};
    for (final day in await _dao.getAllDays()) {
      days.update(
        day.day,
        (seconds) => seconds + day.seconds,
        ifAbsent: () => day.seconds,
      );
    }
    final books = {
      for (final record in await _dao.getAll())
        record.bookName: {
          't': _minus(record.readTime, skip.books[record.bookName]),
          'l': record.lastRead,
        },
    };
    final ownDays = {
      for (final MapEntry(:key, :value) in days.entries)
        key: _minus(value, skip.days[key]),
    };
    if (books.isEmpty && ownDays.isEmpty) return {};
    return {
      deviceId: SyncRecord(
        time: DateTime.now().millisecondsSinceEpoch,
        data: {'books': books, 'days': ownDays},
      ),
    };
  }

  static int _minus(int value, int? restored) {
    final left = value - (restored ?? 0);
    return left < 0 ? 0 : left;
  }

  /// 只收別台的；這台的那筆只有這台寫。
  @override
  bool canApply(String key, SyncRecord? local) => key != _deviceId;

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final others = await _bases.readJson(othersFile);
    for (final MapEntry(:key, value: record) in remote.entries) {
      if (record.deleted) {
        others.remove(key);
      } else {
        others[key] = record.data;
      }
    }
    await _bases.writeJson(othersFile, others);
    return remote;
  }

  /// 別台讀的時間，閱讀統計頁加進這台的。還原進來的那台在雲端也有一筆時，
  /// 扣掉還原的部分（這台的統計裡已經有了）。
  static Future<OtherDevicesStats> others({
    SyncBaseStorage? bases,
    SharedPreferences? prefs,
  }) async {
    final json = await (bases ?? SyncBaseStorage()).readJson(othersFile);
    final books = <String, ({int readTime, int lastRead})>{};
    final days = <String, int>{};
    int asInt(Object? value) => value is int && value > 0 ? value : 0;
    for (final device in json.values) {
      if (device is! Map) continue;
      if (device['books'] case final Map deviceBooks) {
        for (final MapEntry(:key, :value) in deviceBooks.entries) {
          if (value is! Map) continue;
          final current = books['$key'];
          final lastRead = asInt(value['l']);
          books['$key'] = (
            readTime: (current?.readTime ?? 0) + asInt(value['t']),
            lastRead: current == null || lastRead > current.lastRead
                ? lastRead
                : current.lastRead,
          );
        }
      }
      if (device['days'] case final Map deviceDays) {
        for (final MapEntry(:key, :value) in deviceDays.entries) {
          days.update(
            '$key',
            (seconds) => seconds + asInt(value),
            ifAbsent: () => asInt(value),
          );
        }
      }
    }
    final restored = RestoredStats.read(prefs ?? getIt<SharedPreferences>());
    if (restored != null && json.containsKey(restored.from)) {
      for (final MapEntry(:key, :value) in restored.books.entries) {
        if (books[key] case final book?) {
          books[key] = (
            readTime: _minus(book.readTime, value),
            lastRead: book.lastRead,
          );
        }
      }
      for (final MapEntry(:key, :value) in restored.days.entries) {
        if (days[key] case final seconds?) days[key] = _minus(seconds, value);
      }
    }
    return OtherDevicesStats(books: books, days: days);
  }
}

/// 從另一台的備份還原進來的閱讀統計：那台在同步裡的名字（[from]），與還原
/// 時每本書的累計秒數、每天的秒數（所有書加總）。記在這台的偏好設定。
class RestoredStats {
  const RestoredStats({
    required this.from,
    required this.books,
    required this.days,
  });

  static const RestoredStats none = RestoredStats(
    from: '',
    books: {},
    days: {},
  );

  static const String _key = 'sync.restored_stats';

  final String from;
  final Map<String, int> books;
  final Map<String, int> days;

  /// 還原備份後記下；備份那台沒用過同步（[from] 是 null）時，那些時間不在
  /// 雲端任何一筆裡，算這台的，不記。
  static Future<void> remember(
    SharedPreferences prefs, {
    required String? from,
    required List<ReadRecord> records,
    required List<ReadDay> days,
  }) async {
    if (from == null || from.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    final perDay = <String, int>{};
    for (final day in days) {
      perDay.update(
        day.day,
        (seconds) => seconds + day.seconds,
        ifAbsent: () => day.seconds,
      );
    }
    await prefs.setString(
      _key,
      jsonEncode({
        'from': from,
        'books': {
          for (final record in records) record.bookName: record.readTime,
        },
        'days': perDay,
      }),
    );
  }

  static RestoredStats? read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['from'] is! String) return null;
      Map<String, int> ints(Object? value) => {
        if (value is Map)
          for (final MapEntry(:key, :value) in value.entries)
            if (value is int) '$key': value,
      };
      return RestoredStats(
        from: json['from'] as String,
        books: ints(json['books']),
        days: ints(json['days']),
      );
    } on FormatException {
      return null;
    }
  }
}

/// 別台加起來的閱讀統計：每本書的累計秒數與最後閱讀時間，每天的秒數
/// （所有書加總，鍵是 `ReadRecordDao.dayKey`）。
class OtherDevicesStats {
  const OtherDevicesStats({required this.books, required this.days});

  static const OtherDevicesStats empty = OtherDevicesStats(books: {}, days: {});

  final Map<String, ({int readTime, int lastRead})> books;
  final Map<String, int> days;

  /// [from] 到 [to]（含）每天的秒數加總。
  int secondsBetween(String from, String to) => days.entries
      .where((e) => e.key.compareTo(from) >= 0 && e.key.compareTo(to) <= 0)
      .fold(0, (sum, e) => sum + e.value);
}
