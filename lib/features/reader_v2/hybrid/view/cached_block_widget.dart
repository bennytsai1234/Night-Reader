import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart' show PipelineOwner;

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
    _releaseParagraph();
    _blockKey = value;
    _retainParagraph();
    markNeedsLayout();
  }

  set epoch(LayoutEpoch value) {
    if (_epoch == value) return;
    _releaseParagraph();
    _epoch = value;
    _retainParagraph();
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
    _releaseParagraph();
    _paragraphCache = value;
    _retainParagraph();
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

  ParagraphLease? _paragraph;

  void _retainParagraph() {
    if (!attached) return;
    _paragraph = _paragraphCache.retain(
      _blockKey,
      _epoch,
      onChanged: markNeedsPaint,
    );
  }

  void _releaseParagraph() {
    _paragraph?.release();
    _paragraph = null;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _retainParagraph();
  }

  @override
  void detach() {
    _releaseParagraph();
    super.detach();
  }

  @override
  void dispose() {
    _releaseParagraph();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final entry = _paragraph?.entry;
    if (entry == null) return;
    final canvas = context.canvas;

    // 同一個連續排版 group 的多個 block 共用一個 ui.Paragraph；本 block
    // 只是那個 Paragraph 裡 [entry.localTop, entry.localTop + size.height)
    // 這一段的視窗，往上平移 localTop 再貼齊 clip 邊界即可，group 內其他
    // block 的內容自然落在 clip 之外不會被畫出。
    final paragraphOffset = offset - Offset(0, entry.localTop);

    // Paragraph 的實際像素永遠限制在 DocumentIndex 配給這個 block 的
    // extent 內。即使快取重建期間幾何短暫失配，也不能把文字畫進下一塊。
    canvas.save();
    canvas.clipRect(offset & size);
    if (entry.bakedColor == _textColor) {
      // 熱路徑：色已烘進 Paragraph，直繪零離屏。
      canvas.drawParagraph(entry.paragraph, paragraphOffset);
      canvas.restore();
      return;
    }
    // 換色過渡幀：pump 尚未以新色重建本 block，暫以 tint 維持視覺正確。
    // saveLayer 極昂貴，僅允許出現在這條收斂中的路徑。
    canvas.saveLayer(
      offset & size,
      Paint()..colorFilter = ColorFilter.mode(_textColor, BlendMode.srcIn),
    );
    canvas.drawParagraph(entry.paragraph, paragraphOffset);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool get isRepaintBoundary => true;
}
