import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/chapter/reader_v2_illustration.dart';

/// 一張插圖在它那一塊裡的位置（docs/design/reader.md「插圖」）：照原尺寸
/// （圖檔像素 ÷ 像素密度），不放大；比正文欄寬就等比縮到欄寬，比正文區
/// 高就等比縮到正文區高；置中，上下各留 [gap]。
final class IllustrationBox {
  const IllustrationBox({
    required this.rect,
    required this.blockHeight,
    required this.decodeWidth,
  });

  factory IllustrationBox.layout(
    ReaderV2Illustration illustration, {
    required double contentWidth,
    required double maxHeight,
    required double devicePixelRatio,
    required double gap,
    double trailingSpacing = 0,
  }) {
    final ratio = devicePixelRatio > 0 ? devicePixelRatio : 1.0;
    var width = illustration.pixelWidth / ratio;
    var height = illustration.pixelHeight / ratio;
    if (contentWidth > 0 && width > contentWidth) {
      height = height * contentWidth / width;
      width = contentWidth;
    }
    if (maxHeight > 0 && height > maxHeight) {
      width = width * maxHeight / height;
      height = maxHeight;
    }
    width = math.max(1.0, width);
    height = math.max(1.0, height);
    final left = math.max(0.0, (contentWidth - width) / 2);
    return IllustrationBox(
      rect: ui.Rect.fromLTWH(left, gap, width, height),
      blockHeight: gap * 2 + height + trailingSpacing,
      decodeWidth: math.max(1, (width * ratio).round()),
    );
  }

  /// 圖在這一塊裡的位置（塊的左上角是原點）。
  final ui.Rect rect;
  final double blockHeight;

  /// 解碼成多寬（像素）：照畫出來的大小，不解原圖。
  final int decodeWidth;
}

/// 解碼好的插圖，照最近用到的留著幾張（每張照畫出來的大小解碼）。
///
/// 插圖解碼好才交給排版（[HybridLayoutPipeline]），所以紙掀開時圖一定畫得
/// 出來；被擠掉的那張再畫到時重新解碼，好了才補畫。
final class IllustrationImages {
  IllustrationImages({this.capacity = 16}) : assert(capacity > 0);

  static final IllustrationImages instance = IllustrationImages();

  final int capacity;
  final LinkedHashMap<_ImageKey, ui.Image> _images =
      LinkedHashMap<_ImageKey, ui.Image>();
  final Map<_ImageKey, Future<ui.Image?>> _loading = {};

  /// 解不開的圖（讀得出大小、整張卻壞了）：這次開 App 不再一再重解。
  final Set<_ImageKey> _failed = {};

  /// 已經解碼好的那張；不在時回傳 null。
  ui.Image? peek(String path, int width) {
    final key = _ImageKey(path, width);
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key] = image;
    return image;
  }

  /// 解碼 [path]，寬 [width] 像素；讀不到或解不開時是 null。
  Future<ui.Image?> load(String path, int width) {
    final key = _ImageKey(path, width);
    final ready = peek(path, width);
    if (ready != null) return Future.value(ready);
    if (_failed.contains(key)) return Future.value();
    return _loading.putIfAbsent(key, () async {
      try {
        final image = await _decode(path, width);
        if (image != null) {
          _put(key, image);
        } else if (await File(path).exists()) {
          _failed.add(key);
        }
        return image;
      } finally {
        unawaited(Future.microtask(() => _loading.remove(key)));
      }
    });
  }

  void _put(_ImageKey key, ui.Image image) {
    _images.remove(key)?.dispose();
    _images[key] = image;
    while (_images.length > capacity) {
      // 已經畫進圖層的不受影響：圖層自己留著一份。
      _images.remove(_images.keys.first)?.dispose();
    }
  }

  static Future<ui.Image?> _decode(String path, int width) async {
    ui.Codec? codec;
    try {
      // 緩衝交給 instantiateImageCodecFromBuffer 之後由它釋放，成功或失敗
      // 都是，這裡不再釋放。
      codec = await ui.instantiateImageCodecFromBuffer(
        await ui.ImmutableBuffer.fromFilePath(path),
        targetWidth: width,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } on Exception {
      return null;
    } finally {
      codec?.dispose();
    }
  }

  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}

final class _ImageKey {
  const _ImageKey(this.path, this.width);

  final String path;
  final int width;

  @override
  bool operator ==(Object other) =>
      other is _ImageKey && other.path == path && other.width == width;

  @override
  int get hashCode => Object.hash(path, width);
}
