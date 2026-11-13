import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';

import 'comic_page_source.dart';

/// 一張圖照某個寬度解碼的身分。
@immutable
class ComicImageKey {
  const ComicImageKey(this.chapterIndex, this.page, this.width);

  final int chapterIndex;
  final ComicPage page;

  /// 解碼寬度（實體像素）：比它寬的圖縮到這個寬，窄的照原尺寸。
  final int width;

  @override
  bool operator ==(Object other) =>
      other is ComicImageKey &&
      other.chapterIndex == chapterIndex &&
      other.page.name == page.name &&
      other.width == width;

  @override
  int get hashCode => Object.hash(chapterIndex, page.name, width);

  @override
  String toString() => 'ComicImageKey($chapterIndex, ${page.name}, $width)';
}

/// 條漫解碼好的圖（`docs/design/comics.md`「預載」）：照文字閱讀器「畫面
/// 上下固定範圍先準備好、範圍外放掉」的做法（`AdmissionController` 的
/// 3000 點），由條漫告訴它範圍內有哪些圖（[demand]），它照順序讀圖、解碼、
/// 留著；離開範圍、也沒有人在畫的圖馬上放掉，記憶體的上限就是這個範圍。
///
/// 不用 Flutter 的圖片快取：它照最近用到的擠掉，不知道哪些圖離畫面近，
/// 範圍外的也不會主動放掉。
///
/// 圖由 [ComicPageView]（`comic_page_image.dart`）畫：已經解碼好的直接畫
/// （[image]），還沒的登記（[addListener]、[want]），好了或失敗時通知。
class ComicPageImages {
  ComicPageImages({required this.source, this.onSize, this.concurrency = 3})
    : assert(concurrency > 0);

  final ComicPageSource source;

  /// 一張圖解碼好時，回報它的比例（高 ÷ 寬）。
  final void Function(ComicImageKey key, double aspectRatio)? onSize;

  /// 同時讀圖、解碼幾張。在畫面上的（[isVisible]）不受這個限制、馬上開始：
  /// 快速甩過之後，佔著位置的常是已經用不到的圖，眼前那張不排在它們後面。
  /// 畫面外已經建好、要畫的只排到最前面，照樣受限：甩動時一次建好一整個
  /// 螢幕，全部馬上開始會讓解碼擠在一起。
  final int concurrency;

  final Map<ComicImageKey, ui.Image> _ready = {};
  final Map<ComicImageKey, Object> _failed = {};
  final Set<ComicImageKey> _running = {};

  /// 預載時（沒有人在畫）載不到的：不記成失敗、也不再排進預載，免得一再
  /// 打書源；捲到、開始畫它時（[want]）再試一次。
  final Set<ComicImageKey> _speculativeFailed = {};

  /// 範圍內要準備的，照順序（看得到的、往下的、往上的）。
  Set<ComicImageKey> _window = const {};

  /// 範圍裡現在在畫面上的那幾張。
  Set<ComicImageKey> _visible = const {};
  final Queue<ComicImageKey> _queue = Queue();
  final Map<ComicImageKey, List<VoidCallback>> _listeners = {};
  bool _disposed = false;

  int _heldBytes = 0;
  int _peakBytes = 0;

  /// 留著的解碼圖佔幾個位元組（寬 × 高 × 4）。
  int get heldBytes => _heldBytes;

  /// [heldBytes] 到過的最高值。
  int get peakBytes => _peakBytes;

  /// 解碼好的 [key]，給呼叫端自己的一份（用完 `dispose`）；還沒好是 null。
  ui.Image? image(ComicImageKey key) => _ready[key]?.clone();

  /// [key] 載不到的原因；沒有失敗是 null。
  Object? error(ComicImageKey key) => _failed[key];

  void addListener(ComicImageKey key, VoidCallback listener) =>
      (_listeners[key] ??= []).add(listener);

  void removeListener(ComicImageKey key, VoidCallback listener) {
    final listeners = _listeners[key];
    if (listeners == null) return;
    listeners.remove(listener);
    if (listeners.isEmpty) {
      _listeners.remove(key);
      _releaseIfUnneeded(key);
    }
  }

  /// 有人要畫 [key]：還沒開始的排到最前面，在畫面上的馬上開始（見
  /// [concurrency]）。預載時載不到的再試一次。
  void want(ComicImageKey key) {
    if (_disposed || _ready.containsKey(key) || _failed.containsKey(key)) {
      return;
    }
    _speculativeFailed.remove(key);
    if (_running.contains(key)) return;
    _queue.remove(key);
    if (_visible.contains(key)) {
      _start(key);
    } else {
      _queue.addFirst(key);
      _pump();
    }
  }

  /// 載不到的 [key] 再試一次（「重試」、登入回來）。
  void retry(ComicImageKey key) {
    _failed.remove(key);
    want(key);
  }

  /// [key] 現在在畫面上（最近一次 [demand] 的前 visibleCount 張）。在畫面
  /// 外解碼好的圖不淡入：沒有人看到它的骨架。
  bool isVisible(ComicImageKey key) => _visible.contains(key);

  /// 範圍內要準備的圖換成 [ordered]（照先後，前 [visibleCount] 張在畫面
  /// 上）：範圍外、沒有人在畫的放掉，還沒開始的照新的順序排。
  void demand(List<ComicImageKey> ordered, {int visibleCount = 0}) {
    if (_disposed) return;
    final window = ordered.toSet();
    _window = window;
    _visible = ordered.take(visibleCount).toSet();
    _ready.keys
        .where((key) => !window.contains(key))
        .toList()
        .forEach(_releaseIfUnneeded);
    _queue.clear();
    for (final key in ordered) {
      if (_ready.containsKey(key) ||
          _failed.containsKey(key) ||
          _running.contains(key) ||
          _speculativeFailed.contains(key)) {
        continue;
      }
      _queue.add(key);
    }
    for (final key in _visible) {
      if (_queue.remove(key)) _start(key);
    }
    _pump();
  }

  void _pump() {
    while (!_disposed && _running.length < concurrency && _queue.isNotEmpty) {
      _start(_queue.removeFirst());
    }
  }

  void _start(ComicImageKey key) {
    _running.add(key);
    unawaited(_load(key));
  }

  bool _needed(ComicImageKey key) =>
      _window.contains(key) || _listeners.containsKey(key);

  Future<void> _load(ComicImageKey key) async {
    ui.Image? image;
    Object? failure;
    try {
      image = await _decode(key);
    } catch (error) {
      failure = error;
    }
    _running.remove(key);
    if (_disposed) {
      image?.dispose();
      return;
    }
    if (image != null) {
      if (_needed(key)) {
        _ready[key] = image;
        _heldBytes += _bytesOf(image);
        if (_heldBytes > _peakBytes) _peakBytes = _heldBytes;
        if (image.width > 0) onSize?.call(key, image.height / image.width);
      } else {
        image.dispose();
      }
    } else if (_listeners.containsKey(key)) {
      _failed[key] = failure!;
    } else {
      _speculativeFailed.add(key);
    }
    _notify(key);
    _pump();
  }

  Future<ui.Image> _decode(ComicImageKey key) async {
    final bytes = await source.bytesOf(key.chapterIndex, key.page);
    // 緩衝交給 instantiateImageCodecWithSize 之後由它釋放。
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) => width > key.width
          ? ui.TargetImageSize(width: key.width)
          : const ui.TargetImageSize(),
    );
    try {
      // 只取第一格：漫畫的 GIF 幾乎都是靜態圖。
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  void _releaseIfUnneeded(ComicImageKey key) {
    if (_needed(key)) return;
    final image = _ready.remove(key);
    if (image == null) return;
    _heldBytes -= _bytesOf(image);
    // 已經畫在畫面上的不受影響：[ComicPageView] 自己留著一份。
    image.dispose();
  }

  static int _bytesOf(ui.Image image) => image.width * image.height * 4;

  void _notify(ComicImageKey key) {
    final listeners = _listeners[key];
    if (listeners == null) return;
    for (final listener in List.of(listeners)) {
      listener();
    }
  }

  void dispose() {
    _disposed = true;
    for (final image in _ready.values) {
      image.dispose();
    }
    _ready.clear();
    _queue.clear();
    _listeners.clear();
    _heldBytes = 0;
  }
}
