import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/services/local_book_service.dart';

void main() {
  test('LocalBookService imports UMD chapters with readable content', () async {
    final file = File(
      '${Directory.systemTemp.path}/inkpage_test_${DateTime.now().microsecondsSinceEpoch}.umd',
    );
    await file.writeAsBytes(_buildSimpleUmd());

    try {
      final result = await LocalBookService().importBook(file.path);
      expect(result, isNotNull);
      expect(result!.book.name, '測試 UMD');
      expect(result.book.author, '作者');
      expect(result.chapters, hasLength(1));
      expect(result.chapters.first.title, '第一章');
      final content = await LocalBookService().getContent(
        result.book,
        result.chapters.first,
      );
      expect(content, contains('這是正文'));
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  });
}

Uint8List _buildSimpleUmd() {
  final contentBytes = Uint8List.fromList(_utf16le('這是正文\u2029第二行'));
  final compressed = ZLibEncoder().convert(contentBytes);

  final bytes = BytesBuilder();
  bytes.add([0x89, 0x9b, 0x9a, 0xde]);
  bytes.add(_section(2, _utf16le('測試 UMD')));
  bytes.add(_section(3, _utf16le('作者')));
  bytes.add(_section(11, _int32(contentBytes.length)));

  const titleCheck = 0x11223344;
  bytes.add(_sectionWithCheck(132, titleCheck));
  bytes.add(_additional(titleCheck, [6, ..._utf16le('第一章')]));

  const offsetCheck = 0x55667788;
  bytes.add(_sectionWithCheck(131, offsetCheck));
  bytes.add(_additional(offsetCheck, _int32(0)));

  const contentCheck = 0x99aabbcc;
  bytes.add(_sectionWithCheck(132, contentCheck));
  bytes.add(_additional(0x01020304, compressed));

  bytes.add(_section(12, _int32(0)));
  return bytes.toBytes();
}

List<int> _section(int type, List<int> payload, {int flag = 0}) {
  return [
    0x23,
    type & 0xff,
    (type >> 8) & 0xff,
    flag,
    payload.length + 5,
    ...payload,
  ];
}

List<int> _sectionWithCheck(int type, int check, {int flag = 1}) {
  return [0x23, type & 0xff, (type >> 8) & 0xff, flag, 9, ..._int32(check)];
}

List<int> _additional(int check, List<int> payload) {
  return [0x24, ..._int32(check), ..._int32(payload.length + 9), ...payload];
}

List<int> _utf16le(String value) {
  final units = <int>[];
  for (final codeUnit in value.codeUnits) {
    units.add(codeUnit & 0xff);
    units.add((codeUnit >> 8) & 0xff);
  }
  return units;
}

List<int> _int32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];
