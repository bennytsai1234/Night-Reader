import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';

import 'sync_base_storage.dart';
import 'sync_kind.dart';
import 'sync_records.dart';
import 'sync_settings.dart';

/// 閱讀統計的同步：各台分開記，一台一筆，只有那一台自己寫；閱讀統計頁
/// 顯示這台的加上別台的（ADR 0039）。兩台同時讀也不會互相蓋掉秒數。
class ReadStatsSync extends SyncKind {
  ReadStatsSync({
    required this._settings,
    required this._bases,
    ReadRecordDao? dao,
  }) : _dao = dao ?? getIt<ReadRecordDao>();

  final SyncSettings _settings;
  final SyncBaseStorage _bases;
  final ReadRecordDao _dao;

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

  @override
  Future<Map<String, SyncRecord>> local() async {
    final deviceId = _deviceId ??= await _settings.deviceId();
    final days = <String, int>{};
    for (final day in await _dao.getAllDays()) {
      days.update(
        day.day,
        (seconds) => seconds + day.seconds,
        ifAbsent: () => day.seconds,
      );
    }
    final records = await _dao.getAll();
    if (records.isEmpty && days.isEmpty) return {};
    return {
      deviceId: SyncRecord(
        time: 0,
        data: {
          'books': {
            for (final record in records)
              record.bookName: {'t': record.readTime, 'l': record.lastRead},
          },
          'days': days,
        },
      ),
    };
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

  /// 別台讀的時間，閱讀統計頁加進這台的。
  static Future<OtherDevicesStats> others({SyncBaseStorage? bases}) async {
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
    return OtherDevicesStats(books: books, days: days);
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
