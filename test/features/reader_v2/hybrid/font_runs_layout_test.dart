import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

/// 選了下載的字型（ADR 0045）：系統字型自己就有漢字時，漢字還是畫成下載的
/// 字型，英數字照舊系統字型。
///
/// 系統字型用一套真的中文字型的標準粗細，「下載的字型」用同一套的粗體，
/// 兩者畫出的漢字不同、英數字也不同，看像素就知道每個字落在哪一套。
const _downloaded = 'TestDownloadedCjk';
const _layout = ReaderParagraphLayout();

const _cjkFontPairs = <List<String>>[
  ['C:/Windows/Fonts/msjh.ttc', 'C:/Windows/Fonts/msjhbd.ttc'],
  [
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
  ],
];

Future<void> _load(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

Future<Uint8List> _render(String text, {String? fontFamily}) async {
  final paragraph = _layout.build(
    sourceText: text,
    textMap: ParagraphTextMap(sourceLength: text.length, indentLength: 0),
    textStyle: HybridBlockTextStyle(
      fontSize: 40,
      lineHeight: 1.5,
      letterSpacing: 0,
      fontFamily: fontFamily,
    ),
    contentWidth: 600,
    cellWidth: 40,
    textColor: const ui.Color(0xFF000000),
  );
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawParagraph(paragraph, ui.Offset.zero);
  final image = await recorder.endRecording().toImage(600, 80);
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  paragraph.dispose();
  return bytes;
}

void main() {
  final pair = _cjkFontPairs
      .where((paths) => paths.every((path) => File(path).existsSync()))
      .firstOrNull;

  setUpAll(() async {
    if (pair == null) return;
    await _load('sans-serif', pair[0]);
    await _load(_downloaded, pair[1]);
    await _load(
      kReaderV2PunctFontFamily,
      'assets/fonts/NightReaderPunct-Regular.ttf',
    );
  });

  test(
    'CJK draws in the downloaded font even when sans-serif has CJK',
    () async {
      expect(
        listEquals(
          await _render('臺灣頭髮'),
          await _render('臺灣頭髮', fontFamily: _downloaded),
        ),
        isFalse,
      );
      expect(
        listEquals(
          await _render('臺灣頭髮'),
          await _render('臺灣頭髮', fontFamily: 'NotRegistered'),
        ),
        isTrue,
        reason: '沒註冊的字型照舊系統字型：比的是字型，不是別的差異',
      );
    },
    skip: pair == null ? '找不到中文字型' : false,
  );

  test('Latin letters and digits keep the system font', () async {
    expect(
      listEquals(
        await _render('Abc 2026'),
        await _render('Abc 2026', fontFamily: _downloaded),
      ),
      isTrue,
    );
  }, skip: pair == null ? '找不到中文字型' : false);

  test('readerV2CjkRuns covers CJK, kana and full-width forms only', () {
    expect(readerV2CjkRuns('Ab臺灣12かな！x𠀋'), [
      (start: 2, end: 4),
      (start: 6, end: 9),
      (start: 10, end: 12),
    ]);
    expect(readerV2CjkRuns('Abc 123'), isEmpty);
    // 異體字選擇符跟著前面的漢字，不拆成兩段。
    expect(readerV2CjkRuns('葛\u{E0100}a'), [(start: 0, end: 3)]);
    expect(readerV2CjkRuns('e\u0301'), isEmpty);
  });
}
