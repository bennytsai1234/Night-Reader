import 'package:flutter/widgets.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';

final class CachedBlockWidget extends LeafRenderObjectWidget {
  const CachedBlockWidget({
    super.key,
    required this.blockKey,
    required this.epoch,
    required this.namespace,
    required this.measurementStore,
    required this.paragraphCache,
    this.textColor = const Color(0xFF000000),
  });

  final BlockKey blockKey;
  final LayoutEpoch epoch;
  final MeasurementNamespace namespace;
  final MeasurementStore measurementStore;
  final ParagraphCache paragraphCache;

  /// 期望的文字色。烘色一致時 paint 直繪（零離屏）；主題切換的過渡幀
  /// 以 colorFilter tint 舊 Paragraph，待 pump 以新色重建後收斂。
  /// 色不影響幾何——metrics 與 epoch 皆不失效。
  final Color textColor;

  @override
  RenderCachedBlock createRenderObject(BuildContext context) {
    return RenderCachedBlock(
      blockKey: blockKey,
      epoch: epoch,
      namespace: namespace,
      measurementStore: measurementStore,
      paragraphCache: paragraphCache,
      textColor: textColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCachedBlock renderObject,
  ) {
    renderObject
      ..blockKey = blockKey
      ..epoch = epoch
      ..namespace = namespace
      ..measurementStore = measurementStore
      ..paragraphCache = paragraphCache
      ..textColor = textColor;
  }
}

final class RenderCachedBlock extends RenderBox {
  RenderCachedBlock({
    required BlockKey blockKey,
    required LayoutEpoch epoch,
    required MeasurementNamespace namespace,
    required MeasurementStore measurementStore,
    required ParagraphCache paragraphCache,
    required Color textColor,
  }) : _blockKey = blockKey,
       _epoch = epoch,
       _namespace = namespace,
       _measurementStore = measurementStore,
       _paragraphCache = paragraphCache,
       _textColor = textColor;

  BlockKey _blockKey;
  LayoutEpoch _epoch;
  MeasurementNamespace _namespace;
  MeasurementStore _measurementStore;
  ParagraphCache _paragraphCache;
  Color _textColor;

  set blockKey(BlockKey value) {
    if (_blockKey == value) return;
    _cancelParagraphWait();
    _blockKey = value;
    markNeedsLayout();
  }

  set epoch(LayoutEpoch value) {
    if (_epoch == value) return;
    _cancelParagraphWait();
    _epoch = value;
    markNeedsPaint();
  }

  set namespace(MeasurementNamespace value) {
    if (_namespace == value) return;
    _namespace = value;
    markNeedsLayout();
  }

  set measurementStore(MeasurementStore value) {
    if (identical(_measurementStore, value)) return;
    _measurementStore = value;
    markNeedsLayout();
  }

  set paragraphCache(ParagraphCache value) {
    if (identical(_paragraphCache, value)) return;
    _cancelParagraphWait();
    _paragraphCache = value;
    markNeedsPaint();
  }

  set textColor(Color value) {
    if (_textColor == value) return;
    _textColor = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    // sliver 的 itemExtentBuilder（讀 DocumentIndex admitted metrics）已把
    // 精確高度做成 tight constraints——直接採用，不再讀 MeasurementStore：
    // epoch 換代或章節 invalidate 的過渡幀 store 可能先被清，但已放行
    // block 的座標與 extent 必須維持不變（I3）。
    final double height;
    if (constraints.hasTightHeight) {
      height = constraints.maxHeight;
    } else {
      // 非 sliver 環境（獨立測試佈局）才回退 store。
      height = _measurementStore.get(_namespace, _blockKey)?.height ?? 1.0;
    }
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    size = constraints.constrain(Size(width, height));
  }

  /// paint 撲空後是否已向 [ParagraphCache] 註冊 put-waiter。
  bool _waitingForParagraph = false;

  void _handleParagraphReady() {
    // put() 消費 waiter 即移除註冊，這裡只需重置旗標並請求重繪。
    _waitingForParagraph = false;
    if (attached) markNeedsPaint();
  }

  void _cancelParagraphWait() {
    if (!_waitingForParagraph) return;
    _paragraphCache.removePutWaiter(_blockKey, _epoch, _handleParagraphReady);
    _waitingForParagraph = false;
  }

  @override
  void detach() {
    _cancelParagraphWait();
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final entry = _paragraphCache.acquireEntry(_blockKey, _epoch);
    if (entry == null) {
      // 段落尚未建置或已被 LRU 逐出：extent 由 DocumentIndex 撐著，這幀
      // 只能留白；註冊一次性 waiter，段落補建完成即自動重繪，不再依賴
      // sliver 子項被回收再 materialize 才恢復。
      if (!_waitingForParagraph) {
        _waitingForParagraph = true;
        _paragraphCache.addPutWaiter(_blockKey, _epoch, _handleParagraphReady);
      }
      return;
    }
    _cancelParagraphWait();
    final canvas = context.canvas;
    if (entry.bakedColor == _textColor) {
      // 熱路徑：色已烘進 Paragraph，直繪零離屏。
      canvas.drawParagraph(entry.paragraph, offset);
      return;
    }
    // 換色過渡幀：pump 尚未以新色重建本 block，暫以 tint 維持視覺正確。
    // saveLayer 極昂貴，僅允許出現在這條收斂中的路徑。
    canvas.saveLayer(
      offset & size,
      Paint()..colorFilter = ColorFilter.mode(_textColor, BlendMode.srcIn),
    );
    canvas.drawParagraph(entry.paragraph, offset);
    canvas.restore();
  }

  @override
  bool get isRepaintBoundary => true;
}
