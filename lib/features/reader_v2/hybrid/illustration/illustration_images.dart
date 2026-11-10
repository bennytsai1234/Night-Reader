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
///
/// 圖檔是書源 isolate 寫進書本的插圖資料夾的，這裡收不到通知；「清除已下載
/// 的正文」後重抓會把新圖寫回同一個路徑。所以 [load] 每次先看圖檔的修改時間
/// 與大小，和上次不同就把這個路徑的解碼結果、解不開的記錄、進行中的解碼都
/// 作廢。
final class IllustrationImages {
  IllustrationImages({this.capacity = 16}) : assert(capacity > 0);

  static final IllustrationImages instance = IllustrationImages();

  final int capacity;
  final LinkedHashMap<_ImageKey, ui.Image> _images =
      LinkedHashMap<_ImageKey, ui.Image>();
  final Map<_ImageKey, Future<ui.Image?>> _loading = {};

  /// 解不開的圖（讀得出大小、整張卻壞了）：圖檔沒換就不再一再重解。
  final Set<_ImageKey> _failed = {};

  /// 每個圖檔上次 [load] 時的版本；上面三份記錄都是這個版本的。
  final Map<String, _FileVersion> _versions = {};

  /// 已經解碼好的那張；不在時回傳 null。不看圖檔換了沒有，那是 [load] 的事。
  ui.Image? peek(String path, int width) {
    final key = _ImageKey(path, width);
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key] = image;
    return image;
  }

  /// 解碼 [path]，寬 [width] 像素；讀不到或解不開時是 null。
  Future<ui.Image?> load(String path, int width) async {
    final version = await _FileVersion.of(path);
    _refresh(path, version);
    if (version == null) return null;
    final key = _ImageKey(path, width);
    final ready = peek(path, width);
    if (ready != null) return ready;
    if (_failed.contains(key)) return null;
    return _loading[key] ?? _startDecode(key, version);
  }

  /// 圖檔和上次看到的不同（換了、刪了）就作廢這個路徑的所有記錄。
  void _refresh(String path, _FileVersion? version) {
    if (_versions[path] == version) return;
    if (version == null) {
      _versions.remove(path);
    } else {
      _versions[path] = version;
    }
    _images.removeWhere((key, image) {
      if (key.path != path) return false;
      image.dispose();
      return true;
    });
    _failed.removeWhere((key) => key.path == path);
    _loading.removeWhere((key, _) => key.path == path);
  }

  Future<ui.Image?> _startDecode(_ImageKey key, _FileVersion version) {
    late final Future<ui.Image?> decoding;
    decoding = () async {
      try {
        final image = await _decode(key.path, key.width);
        if (_versions[key.path] != version) {
          // 解碼途中圖檔換了或快取清了：這張是舊檔的，不存，照現在的檔再來。
          image?.dispose();
          return await load(key.path, key.width);
        }
        if (image != null) {
          _put(key, image);
        } else {
          _failed.add(key);
        }
        return image;
      } finally {
        // 圖檔換過時這個位置已經是新檔的解碼。
        _loading.removeWhere((_, future) => identical(future, decoding));
      }
    }();
    _loading[key] = decoding;
    return decoding;
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

  /// 全部作廢：解碼結果、解不開的記錄、看過的版本。進行中的解碼完成時
  /// 不存，照現在的檔再解。
  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _failed.clear();
    _versions.clear();
    _loading.clear();
  }
}

/// 圖檔的版本：修改時間加大小。
final class _FileVersion {
  const _FileVersion(this.modified, this.size);

  /// 沒有這個檔時是 null。
  static Future<_FileVersion?> of(String path) async {
    final stat = await FileStat.stat(path);
    if (stat.type == FileSystemEntityType.notFound) return null;
    return _FileVersion(stat.modified, stat.size);
  }

  final DateTime modified;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is _FileVersion && other.modified == modified && other.size == size;

  @override
  int get hashCode => Object.hash(modified, size);
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
