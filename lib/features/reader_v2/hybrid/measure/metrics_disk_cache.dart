import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

final class MetricsDiskCache {
  MetricsDiskCache({required this.baseDirectory});

  static const int _version = 1;
  static const int _headerMagic = 0x4E52484D; // NRHM

  final Directory baseDirectory;

  Future<int> write({
    required String bookUrl,
    required StyleFingerprint fingerprint,
    required Map<BlockKey, BlockMetrics> metrics,
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
    for (final key in keys) {
      final metric = metrics[key]!;
      final row =
          ByteData(20)
            ..setInt32(0, key.chapterIndex, Endian.big)
            ..setInt32(4, key.blockIndex, Endian.big)
            ..setFloat64(8, metric.height, Endian.big)
            ..setInt32(16, metric.lineCount, Endian.big);
      bytes.add(row.buffer.asUint8List());
    }
    await file.writeAsBytes(bytes.takeBytes(), flush: true);
    return metrics.length;
  }

  Future<Map<BlockKey, BlockMetrics>> read({
    required String bookUrl,
    required StyleFingerprint fingerprint,
  }) async {
    final file = _fileFor(bookUrl: bookUrl, fingerprint: fingerprint);
    if (!await file.exists()) return <BlockKey, BlockMetrics>{};
    final data = await file.readAsBytes();
    if (data.length < 12) return <BlockKey, BlockMetrics>{};
    final header = ByteData.sublistView(data, 0, 12);
    if (header.getUint32(0, Endian.big) != _headerMagic) {
      return <BlockKey, BlockMetrics>{};
    }
    if (header.getUint32(4, Endian.big) != _version) {
      return <BlockKey, BlockMetrics>{};
    }
    final count = header.getUint32(8, Endian.big);
    final expectedLength = 12 + count * 20;
    if (data.length != expectedLength) return <BlockKey, BlockMetrics>{};
    final result = <BlockKey, BlockMetrics>{};
    for (var i = 0; i < count; i += 1) {
      final offset = 12 + i * 20;
      final row = ByteData.sublistView(data, offset, offset + 20);
      final key = BlockKey(
        chapterIndex: row.getInt32(0, Endian.big),
        blockIndex: row.getInt32(4, Endian.big),
      );
      result[key] = BlockMetrics(
        height: row.getFloat64(8, Endian.big),
        lineCount: row.getInt32(16, Endian.big),
      );
    }
    return result;
  }

  Future<int> warmIntoStore({
    required String bookUrl,
    required MeasurementNamespace namespace,
    required void Function(BlockKey key, BlockMetrics metrics) put,
  }) async {
    final entries = await read(
      bookUrl: bookUrl,
      fingerprint: namespace.fingerprint,
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
        sha1.convert(utf8.encode(fingerprint.stableHash.toString())).toString();
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
