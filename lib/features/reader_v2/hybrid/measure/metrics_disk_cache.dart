import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

final class MetricsDiskCache {
  MetricsDiskCache({required this.baseDirectory});

  // v3：縮排前綴從 U+3000 文字改為 placeholder；extent 理論上不變，
  // 升版讓非 1em 全形空白字型的舊快取一次性重量測。
  static const int _version = 3;
  static const int _headerMagic = 0x4E52484D; // NRHM
  static const int _rowSize = 40;

  final Directory baseDirectory;

  Future<int> write({
    required String bookUrl,
    required StyleFingerprint fingerprint,
    required Map<BlockKey, BlockMetrics> metrics,
    Map<int, String> chapterContentHashes = const <int, String>{},
  }) async {
    final file = _fileFor(bookUrl: bookUrl, fingerprint: fingerprint);
    await file.parent.create(recursive: true);
    final bytes = BytesBuilder(copy: false);
    final header =
        ByteData(12)
          ..setUint32(0, _headerMagic, Endian.big)
          ..setUint32(4, _version, Endian.big)
          ..setUint32(8, metrics.length, Endian.big);
    bytes.add(header.buffer.asUint8List());
    final keys = metrics.keys.toList()..sort();
    // 同章數百列共用同一個 digest——逐列重算 sha1 會把幾千列的寫入
    // 從次毫秒拖到十幾毫秒（寫入發生在 UI isolate）。
    final chapterDigests = <int, List<int>>{};
    for (final key in keys) {
      final metric = metrics[key]!;
      final row =
          ByteData(20)
            ..setInt32(0, key.chapterIndex, Endian.big)
            ..setInt32(4, key.blockIndex, Endian.big)
            ..setFloat64(8, metric.height, Endian.big)
            ..setInt32(16, metric.lineCount, Endian.big);
      bytes.add(row.buffer.asUint8List());
      bytes.add(
        chapterDigests[key.chapterIndex] ??=
            sha1
                .convert(
                  utf8.encode(chapterContentHashes[key.chapterIndex] ?? ''),
                )
                .bytes,
      );
    }
    await file.writeAsBytes(bytes.takeBytes(), flush: true);
    return metrics.length;
  }

  Future<Map<BlockKey, BlockMetrics>> read({
    required String bookUrl,
    required StyleFingerprint fingerprint,
    Map<int, String>? chapterContentHashes,
  }) {
    final path = _fileFor(bookUrl: bookUrl, fingerprint: fingerprint).path;
    // 檔案讀取與逐 row 解析搬到背景 isolate：長書的 metrics 檔有數萬
    // row，跨章 warm 發生在 fling 中，不可佔用 UI isolate。
    // BlockKey/BlockMetrics 皆為純值物件，可跨 isolate 傳遞。
    return Isolate.run(() => _parseMetricsFile(path, chapterContentHashes));
  }

  static Map<BlockKey, BlockMetrics> _parseMetricsFile(
    String path,
    Map<int, String>? chapterContentHashes,
  ) {
    final file = File(path);
    if (!file.existsSync()) return <BlockKey, BlockMetrics>{};
    final data = file.readAsBytesSync();
    if (data.length < 12) return <BlockKey, BlockMetrics>{};
    final header = ByteData.sublistView(data, 0, 12);
    if (header.getUint32(0, Endian.big) != _headerMagic) {
      return <BlockKey, BlockMetrics>{};
    }
    if (header.getUint32(4, Endian.big) != _version) {
      return <BlockKey, BlockMetrics>{};
    }
    final count = header.getUint32(8, Endian.big);
    final expectedLength = 12 + count * _rowSize;
    if (data.length != expectedLength) return <BlockKey, BlockMetrics>{};
    // 與寫入端同款記憶化：同章共用同一個 digest，不逐 row 重算。
    final expectedDigests =
        chapterContentHashes == null
            ? null
            : <int, List<int>>{
              for (final entry in chapterContentHashes.entries)
                entry.key: sha1.convert(utf8.encode(entry.value)).bytes,
            };
    final result = <BlockKey, BlockMetrics>{};
    for (var i = 0; i < count; i += 1) {
      final offset = 12 + i * _rowSize;
      final row = ByteData.sublistView(data, offset, offset + 20);
      final chapterIndex = row.getInt32(0, Endian.big);
      if (expectedDigests != null) {
        final expectedDigest = expectedDigests[chapterIndex];
        if (expectedDigest == null) continue;
        final storedDigest = data.sublist(offset + 20, offset + _rowSize);
        if (!_bytesEqual(storedDigest, expectedDigest)) continue;
      }
      final height = row.getFloat64(8, Endian.big);
      final lineCount = row.getInt32(16, Endian.big);
      final blockIndex = row.getInt32(4, Endian.big);
      if (chapterIndex < 0 ||
          blockIndex < 0 ||
          !height.isFinite ||
          height <= 0 ||
          lineCount < 0) {
        continue;
      }
      final key = BlockKey(chapterIndex: chapterIndex, blockIndex: blockIndex);
      result[key] = BlockMetrics(height: height, lineCount: lineCount);
    }
    return result;
  }

  Future<int> warmIntoStore({
    required String bookUrl,
    required MeasurementNamespace namespace,
    required void Function(BlockKey key, BlockMetrics metrics) put,
    Map<int, String>? chapterContentHashes,
  }) async {
    final entries = await read(
      bookUrl: bookUrl,
      fingerprint: namespace.fingerprint,
      chapterContentHashes: chapterContentHashes,
    );
    for (final entry in entries.entries) {
      put(entry.key, entry.value);
    }
    return entries.length;
  }

  File _fileFor({
    required String bookUrl,
    required StyleFingerprint fingerprint,
  }) {
    final bookHash = sha1.convert(utf8.encode(bookUrl)).toString();
    final fingerprintHash =
        sha1.convert(utf8.encode(fingerprint.stableKey)).toString();
    return File(
      p.join(
        baseDirectory.path,
        'hybrid_metrics',
        bookHash,
        '$fingerprintHash.bin',
      ),
    );
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
