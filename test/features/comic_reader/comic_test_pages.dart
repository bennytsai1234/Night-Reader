import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:night_reader/features/comic_reader/comic_page_source.dart';

/// 一張 [width]×[height] 的 PNG：上下兩半兩種顏色，看得出圖的上下緣。
Uint8List stripedPng(int width, int height, int top, int bottom) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // 每列的過濾方式：無。
    final color = y < height / 2 ? top : bottom;
    for (var x = 0; x < width; x++) {
      raw
        ..addByte((color >> 16) & 0xFF)
        ..addByte((color >> 8) & 0xFF)
        ..addByte(color & 0xFF);
    }
  }
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final length = ByteData(4)..setUint32(0, data.length);
    out.add(length.buffer.asUint8List());
    final body = [...type.codeUnits, ...data];
    out.add(body);
    final crc = ByteData(4)..setUint32(0, getCrc32(body));
    out.add(crc.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // 每個顏色 8 位元
    ..setUint8(9, 2); // RGB
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', const ZLibEncoder().encodeBytes(raw.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

const _palette = [0xC0392B, 0x2980B9, 0x27AE60, 0x8E44AD, 0xD35400, 0x16A085];

/// 假的漫畫來源：每話 [pagesPerChapter] 張，記著寬高（或不記，模擬還沒下載
/// 的章節）；可以讓某一話或某一張失敗、延後回應。
class FakeComicSource implements ComicPageSource {
  FakeComicSource({
    this.pagesPerChapter = 4,
    this.width = 60,
    this.height = 90,
    this.knownSizes = true,
  });

  final int pagesPerChapter;
  final int width;
  final int height;
  final bool knownSizes;

  /// 這幾話抓目錄時失敗。
  final Set<int> failingChapters = {};

  /// 這幾張（話, 張）讀圖時失敗。
  final Set<(int, int)> failingPages = {};

  /// 每一話的圖要等外面放行才回（測試載入中）。
  final Map<int, Completer<void>> chapterGates = {};

  /// 每一張圖（話, 張）要等外面放行才回（測試圖晚到）。
  final Map<(int, int), Completer<void>> pageGates = {};

  final List<int> requestedChapters = [];
  final Map<int, Uint8List> _images = {};

  @override
  Future<List<ComicPage>> pagesOf(int chapterIndex) async {
    requestedChapters.add(chapterIndex);
    await chapterGates[chapterIndex]?.future;
    if (failingChapters.contains(chapterIndex)) {
      throw StateError('第 $chapterIndex 話抓不到');
    }
    return [
      for (var i = 0; i < pagesPerChapter; i++)
        ComicPage(
          name: '$chapterIndex-$i.png',
          width: knownSizes ? width : null,
          height: knownSizes ? height : null,
        ),
    ];
  }

  @override
  Future<Uint8List> bytesOf(int chapterIndex, ComicPage page) async {
    final index = int.parse(page.name.split('-').last.split('.').first);
    await pageGates[(chapterIndex, index)]?.future;
    if (failingPages.contains((chapterIndex, index))) {
      throw StateError('圖抓不到');
    }
    final top = _palette[(chapterIndex + index) % _palette.length];
    // 每種顏色只產生一次：量幀預算時不把測試自己做圖的時間算進主執行緒。
    return _images.putIfAbsent(
      top,
      () => stripedPng(width, height, top, top ~/ 2 & 0x7F7F7F),
    );
  }

  @override
  String? webUrlOf(int chapterIndex, ComicPage page) =>
      'https://example.com/$chapterIndex/${page.name}';
}
