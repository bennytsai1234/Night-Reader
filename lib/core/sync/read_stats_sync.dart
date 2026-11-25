import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/app_database.dart' show ReadDay;
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/reading/read_record.dart';
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

  /// 別台的統計有變時加一：閱讀統計頁聽它重讀，開著也看得到別台剛讀的。
  static final ValueNotifier<int> applied = ValueNotifier(0);

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
    final skip = (RestoredStats.read(_prefs) ?? RestoredStats.none).total(
      except: deviceId,
    );
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

  /// 書改名：閱讀統計（`ReadRecordDao.renameBook`）與從別台還原進來的那份
  /// （[RestoredStats.renameBook]）一起從 [from] 併到 [to]，不然還原的時間
  /// 在新書名下會被當成這台讀的再送一次。
  static Future<void> renameBook(
    ReadRecordDao dao, {
    required String from,
    required String to,
    SharedPreferences? prefs,
  }) async {
    await dao.renameBook(from: from, to: to);
    await RestoredStats.renameBook(
      prefs ?? await SharedPreferences.getInstance(),
      from: from,
      to: to,
    );
  }

  /// 只收別台的；這台的那筆只有這台寫。
  @override
  bool canApply(String key, SyncRecord? local) => key != _deviceId;

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final others = await _bases.readJson(othersFile);
    final before = jsonEncode(others);
    for (final MapEntry(:key, value: record) in remote.entries) {
      if (record.deleted) {
        others.remove(key);
      } else {
        others[key] = record.data;
      }
    }
    await _bases.writeJson(othersFile, others);
    if (jsonEncode(others) != before) ReadStatsSync.applied.value++;
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
    final restored =
        (RestoredStats.read(prefs ?? getIt<SharedPreferences>()) ??
                RestoredStats.none)
            .total(only: json.keys.toSet());
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
    return OtherDevicesStats(books: books, days: days);
  }
}

/// 從別台的備份還原進來、這台統計裡有的閱讀時間，照來源那台（它在同步裡的
/// 名字）分開記：每本書的累計秒數、每本書每天的秒數。記在這台的偏好設定，
/// 不進備份（`BackupService.deviceOnlyKeys`）。
///
/// 每一秒最多記在一台下面：還原只換掉備份裡有的書（`restoreReadingStats`），
/// 那幾本照這次的備份重記，其他書原本記的來源不動；書改名時跟著搬
/// （[renameBook]）。
class RestoredStats {
  const RestoredStats(this.devices);

  static const RestoredStats none = RestoredStats({});

  static const String prefKey = 'sync.restored_stats';

  /// 來源那台 → 那台還原進來的每本書累計秒數（`books`）與每本書每天的秒數
  /// （`days`：書名 → 日期 → 秒數）。
  final Map<
    String,
    ({Map<String, int> books, Map<String, Map<String, int>> days})
  >
  devices;

  /// [only] 那幾台（給了的話）、[except] 以外的還原進來的時間：每本書的
  /// 累計秒數，與每天的秒數（所有書加總）。
  ({Map<String, int> books, Map<String, int> days}) total({
    String? except,
    Set<String>? only,
  }) {
    final books = <String, int>{};
    final days = <String, int>{};
    for (final MapEntry(key: device, :value) in devices.entries) {
      if (device == except || only != null && !only.contains(device)) continue;
      for (final MapEntry(:key, value: seconds) in value.books.entries) {
        books.update(key, (sum) => sum + seconds, ifAbsent: () => seconds);
      }
      for (final perDay in value.days.values) {
        for (final MapEntry(:key, value: seconds) in perDay.entries) {
          days.update(key, (sum) => sum + seconds, ifAbsent: () => seconds);
        }
      }
    }
    return (books: books, days: days);
  }

  /// 還原備份後記下：備份裡有的書（累計換成備份的值、每日也照備份重寫）
  /// 原本記在哪台都清掉，再記到 [from] 下面；備份那台沒用過同步（[from] 是
  /// null）時，那些時間不在雲端任何一筆裡，算這台的，不記。
  static Future<void> remember(
    SharedPreferences prefs, {
    required String? from,
    required List<ReadRecord> records,
    required List<ReadDay> days,
  }) async {
    final devices = _mutable(read(prefs) ?? none);
    final replacedBooks = {for (final record in records) record.bookName};
    for (final device in devices.values) {
      for (final book in replacedBooks) {
        device.books.remove(book);
        device.days.remove(book);
      }
      for (final day in days) {
        device.days[day.bookName]?.remove(day.day);
      }
    }
    if (from != null && from.isNotEmpty) {
      final device = devices[from] ??= (books: {}, days: {});
      for (final record in records) {
        device.books[record.bookName] = record.readTime;
      }
      for (final day in days) {
        (device.days[day.bookName] ??= {})[day.day] = day.seconds;
      }
    }
    await _write(prefs, devices);
  }

  /// 書改名（`ReadRecordDao.renameBook` 把 [from] 併進 [to]）：還原進來的
  /// 那份跟著併過去。
  static Future<void> renameBook(
    SharedPreferences prefs, {
    required String from,
    required String to,
  }) async {
    if (from == to) return;
    final restored = read(prefs);
    if (restored == null) return;
    final devices = _mutable(restored);
    for (final device in devices.values) {
      if (device.books.remove(from) case final seconds?) {
        device.books.update(
          to,
          (sum) => sum + seconds,
          ifAbsent: () => seconds,
        );
      }
      if (device.days.remove(from) case final perDay?) {
        final target = device.days[to] ??= {};
        for (final MapEntry(:key, value: seconds) in perDay.entries) {
          target.update(key, (sum) => sum + seconds, ifAbsent: () => seconds);
        }
      }
    }
    await _write(prefs, devices);
  }

  static RestoredStats? read(SharedPreferences prefs) {
    final raw = prefs.getString(prefKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      Map<String, int> ints(Object? value) => {
        if (value is Map)
          for (final MapEntry(:key, :value) in value.entries)
            if (value is int) '$key': value,
      };
      // 2026-11 以前只記最後一次還原的那台，每天的秒數是所有書加總：記在
      // 書名空白下面，照樣扣得到。
      if (json['from'] case final String from) {
        return RestoredStats({
          from: (books: ints(json['books']), days: {'': ints(json['days'])}),
        });
      }
      return RestoredStats({
        if (json['devices'] case final Map devices)
          for (final MapEntry(:key, :value) in devices.entries)
            if (value is Map)
              '$key': (
                books: ints(value['books']),
                days: {
                  if (value['days'] case final Map days)
                    for (final MapEntry(key: book, value: perDay)
                        in days.entries)
                      '$book': ints(perDay),
                },
              ),
      });
    } on FormatException {
      return null;
    }
  }

  static Map<
    String,
    ({Map<String, int> books, Map<String, Map<String, int>> days})
  >
  _mutable(RestoredStats stats) => {
    for (final MapEntry(:key, :value) in stats.devices.entries)
      key: (
        books: {...value.books},
        days: {
          for (final MapEntry(key: book, value: perDay) in value.days.entries)
            book: {...perDay},
        },
      ),
  };

  static Future<void> _write(
    SharedPreferences prefs,
    Map<String, ({Map<String, int> books, Map<String, Map<String, int>> days})>
    devices,
  ) async {
    for (final device in devices.values) {
      device.days.removeWhere((_, perDay) => perDay.isEmpty);
    }
    devices.removeWhere(
      (_, device) => device.books.isEmpty && device.days.isEmpty,
    );
    if (devices.isEmpty) {
      await prefs.remove(prefKey);
      return;
    }
    await prefs.setString(
      prefKey,
      jsonEncode({
        'devices': {
          for (final MapEntry(:key, :value) in devices.entries)
            key: {'books': value.books, 'days': value.days},
        },
      }),
    );
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
