// 細節檢查：骨架換成內容時，每一條骨架是不是剛好就是換上來的那段字（或
// 圖示、圖片）的長度與位置。
//
// 和 `skeleton_match.dart` 不同：那邊拿同一份資料畫的骨架和內容比，檢查骨架
// 的形狀畫得對不對；這裡照真的流程（開書、跳章、進頁面）一格一格推進，記下
// 每一格畫面上骨架的每一條，等骨架換掉後量換上來的內容，抓的是「載入當下
// 手上的資料和最後顯示的不同」，例如章名還沒拿到時骨架整條缺、進度還沒算出
// 來時骨架照「…%」量得太短。
//
// App 裡每一處骨架換場都經過 [SkeletonRevealLayer]（閱讀器頁首頁尾、
// [SkeletonSwitcher]），所以不必知道是哪個畫面：一個骨架層和它旁邊的內容層
// 算一處換場。用法見 `test/polish/`。
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

import 'skeleton_match.dart';

/// 兩條邊的位置差超過這麼多（邏輯像素）才算對不上：骨架和內容照同一份排版
/// 量，對得上時完全一樣，半個像素是存進資料庫再讀出來的小數誤差。
const double kHandoffTolerance = 0.5;

/// 換場後的內容裡的一塊：一行字、一個圖示或一張圖。
class HandoffMark {
  const HandoffMark(this.rect, this.text);

  final Rect rect;

  /// 這一塊是哪段字；圖示與圖片是 null。
  final String? text;

  String get label => text == null ? '圖示或圖片' : '「$text」';
}

/// 一條骨架和換上來的內容對不上的地方。
class HandoffProblem {
  const HandoffProblem(this.kind, this.message, {this.bar, this.real});

  /// `short`（骨架太短）、`long`（太長）、`shifted`（一樣長、位置不同）、
  /// `extra`（骨架多出、換場後那裡沒東西）、`missing`（內容有、骨架沒有）。
  final String kind;
  final String message;
  final Rect? bar;
  final Rect? real;
}

/// 一處換場裡畫面上的一種骨架樣子，以及它在畫面上停了哪幾格。
///
/// [bars] 是相對骨架層左上角的位置：頁面推入、滑動時整層一起移動，不算
/// 骨架變了樣子。[origin] 是截圖那一格骨架層在畫面上的位置：先拍第一格，
/// 頁面還在滑進來時，等它停下來再補拍一張。
class _Snapshot {
  _Snapshot(this.bars, this.firstFrame, this.origin) : lastFrame = firstFrame;

  final List<Rect> bars;
  final int firstFrame;
  Offset origin;
  int lastFrame;
  String? image;

  /// 上一格骨架層的位置，看它停下來了沒有。
  Offset? previousOrigin;
}

/// 一處換場（一個骨架層和旁邊的內容層）。
class _Slot {
  _Slot(this.place, this.area);

  final String place;
  final Rect area;
  final snapshots = <_Snapshot>[];

  /// 換上來的內容，相對內容層左上角（和骨架層疊在同一個位置）。
  List<HandoffMark>? content;
  Offset contentOrigin = Offset.zero;
  int? contentFrame;
  String? contentImage;

  /// 骨架拿掉時整處換場也一起拿掉了（例如退出頁面），量不到內容。
  bool gone = false;
}

/// 一段操作裡每一處骨架換場的紀錄。每推進一格呼叫一次 [observe]。
class SkeletonHandoffWatch {
  SkeletonHandoffWatch({this.capture});

  /// 每種骨架樣子第一次出現、以及換場後量內容的那一格，拿這一格存一張
  /// 截圖，傳回檔名（給 `tool/polish_viewer/` 做頁面）；null 時不存。
  final Future<String> Function(String name)? capture;

  final _slots = <Element, _Slot>{};
  var _frame = 0;

  /// 看過至少一處換場，而且每一處都換完了。
  bool get done =>
      _slots.isNotEmpty &&
      _slots.values.every((slot) => slot.content != null || slot.gone);

  bool get sawAny => _slots.isNotEmpty;

  Future<void> observe(WidgetTester tester) async {
    _frame += 1;
    final present = <Element>{};
    final shots = <(String, void Function(String))>[];
    for (final element in find.byType(SkeletonRevealLayer).evaluate()) {
      final layer = element.widget as SkeletonRevealLayer;
      if (layer.side != SkeletonRevealSide.skeleton) continue;
      final parent = _parentOf(element);
      final slot = _slots.putIfAbsent(
        parent,
        () => _Slot(_placeOf(element), _rectOf(element)),
      );
      // 骨架完全淡掉的那幾格看不到，不算畫面上的樣子；換完前又出現（例如
      // 換場途中再載入）時從頭等內容。
      if (layer.presence.value <= 0) continue;
      present.add(parent);
      slot.content = null;
      final origin = _rectOf(element).topLeft;
      final bars = [
        for (final bar in _barsUnder(tester, element)) bar.shift(-origin),
      ];
      final last = slot.snapshots.isEmpty ? null : slot.snapshots.last;
      if (last != null && _sameBars(last.bars, bars)) {
        last.lastFrame = _frame;
        final settled = last.previousOrigin == origin;
        last.previousOrigin = origin;
        if (settled && last.origin != origin) {
          last.origin = origin;
          final index = _slots.values.toList().indexOf(slot);
          shots.add((
            'slot$index-skeleton${slot.snapshots.length}',
            (file) => last.image = file,
          ));
        }
      } else {
        final snapshot = _Snapshot(bars, _frame, origin);
        slot.snapshots.add(snapshot);
        final index = _slots.values.toList().indexOf(slot);
        shots.add((
          'slot$index-skeleton${slot.snapshots.length}',
          (file) => snapshot.image = file,
        ));
      }
    }
    for (final (index, MapEntry(key: parent, value: slot))
        in _slots.entries.indexed) {
      if (present.contains(parent) || slot.content != null) continue;
      if (slot.snapshots.isEmpty) continue;
      final content = parent.mounted ? _contentLayerUnder(parent) : null;
      if (content == null) {
        slot.gone = true;
        continue;
      }
      final origin = _rectOf(content).topLeft;
      slot
        ..content = [
          for (final mark in _marksUnder(tester, content))
            HandoffMark(mark.rect.shift(-origin), mark.text),
        ]
        ..contentOrigin = origin
        ..contentFrame = _frame;
      shots.add(('slot$index-content', (file) => slot.contentImage = file));
    }
    final capture = this.capture;
    if (capture == null) return;
    for (final (name, done) in shots) {
      done(await capture(name));
    }
  }

  /// 對不上的地方，一處換場一段；空的就是每一處都對得上。
  List<String> findings() {
    final out = <String>[];
    for (final slot in _slots.values) {
      final content = slot.content;
      if (content == null) {
        if (!slot.gone) out.add('${slot.place}：骨架一直沒換成內容');
        continue;
      }
      final lines = <String>[];
      for (final (i, snapshot) in slot.snapshots.indexed) {
        final problems = compareBars(snapshot.bars, content);
        if (problems.isEmpty) continue;
        lines.add(
          '  骨架的第 ${i + 1} 種樣子（共 ${slot.snapshots.length} 種，'
          '${_frames(snapshot)}）：',
        );
        lines.addAll(problems.map((p) => '    ${p.message}'));
      }
      if (lines.isNotEmpty) out.add('${slot.place}\n${lines.join('\n')}');
    }
    return out;
  }

  /// 給 `tool/polish_viewer/` 的資料：每處換場的每種骨架樣子、換上來的內容
  /// 與對不上的地方，座標是手機邏輯像素。骨架、內容與問題的方框都相對那一
  /// 層的左上角，加上 `origin`（骨架那一格）或 `contentOrigin`（換場後那一
  /// 格）就是截圖上的位置。
  List<Map<String, Object?>> toJson() => [
    for (final slot in _slots.values)
      if (!slot.gone || slot.content != null)
        {
          'place': slot.place,
          'area': _rectJson(slot.area),
          'contentOrigin': [slot.contentOrigin.dx, slot.contentOrigin.dy],
          'contentFrame': slot.contentFrame,
          'contentImage': slot.contentImage,
          'content': [
            for (final mark in slot.content ?? const <HandoffMark>[])
              {'rect': _rectJson(mark.rect), 'text': mark.text},
          ],
          'snapshots': [
            for (final snapshot in slot.snapshots)
              {
                'firstFrame': snapshot.firstFrame,
                'lastFrame': snapshot.lastFrame,
                'origin': [snapshot.origin.dx, snapshot.origin.dy],
                'image': snapshot.image,
                'bars': [for (final bar in snapshot.bars) _rectJson(bar)],
                'problems': [
                  if (slot.content case final content?)
                    for (final p in compareBars(snapshot.bars, content))
                      {
                        'kind': p.kind,
                        'message': p.message,
                        'bar': p.bar == null ? null : _rectJson(p.bar!),
                        'real': p.real == null ? null : _rectJson(p.real!),
                      },
                ],
              },
          ],
          if (slot.content == null) 'stuck': true,
        },
  ];
}

String _frames(_Snapshot snapshot) => snapshot.firstFrame == snapshot.lastFrame
    ? '第 ${snapshot.firstFrame} 格'
    : '第 ${snapshot.firstFrame}–${snapshot.lastFrame} 格';

List<double> _rectJson(Rect r) => [
  for (final v in [r.left, r.top, r.width, r.height]) (v * 10).round() / 10,
];

/// 點下去（[action]）之後一格一格推進（16ms），直到每一處換場都換完、再停
/// [tailFrames] 格。資料庫在真的 isolate 裡，每格讓出一點真實時間。推了
/// [maxFrames] 格還沒換完也停下來，還在骨架的地方會列進
/// [SkeletonHandoffWatch.findings]。
Future<SkeletonHandoffWatch> watchSkeletonHandoffs(
  WidgetTester tester,
  Future<void> Function() action, {
  Future<String> Function(String name)? capture,
  int maxFrames = 900,
  int tailFrames = 30,
}) async {
  final watch = SkeletonHandoffWatch(capture: capture);
  await action();
  var quiet = 0;
  for (var i = 0; i < maxFrames && quiet < tailFrames; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
    await watch.observe(tester);
    quiet = watch.done ? quiet + 1 : 0;
  }
  return watch;
}

/// 每一條骨架和換上來的內容比：同一行、橫向有重疊的內容合起來算這一條要
/// 換成的東西（例如電量的圖示加數字是一條），左右兩緣都要對齊。
List<HandoffProblem> compareBars(List<Rect> bars, List<HandoffMark> content) {
  String span(Rect r) =>
      '${r.left.toStringAsFixed(1)}–${r.right.toStringAsFixed(1)}'
      '（寬 ${r.width.toStringAsFixed(1)}）';
  final out = <HandoffProblem>[];
  final used = <HandoffMark>{};
  for (final bar in bars) {
    final covered = [
      for (final mark in content)
        if ((mark.rect.center.dy - bar.center.dy).abs() <
                math.max(bar.height, mark.rect.height) / 2 &&
            mark.rect.left < bar.right &&
            mark.rect.right > bar.left)
          mark,
    ];
    if (covered.isEmpty) {
      out.add(
        HandoffProblem('extra', '骨架多出一條 ${span(bar)}，換場後那裡沒有東西', bar: bar),
      );
      continue;
    }
    used.addAll(covered);
    final real = covered
        .map((mark) => mark.rect)
        .reduce((a, b) => a.expandToInclude(b));
    if ((real.left - bar.left).abs() <= kHandoffTolerance &&
        (real.right - bar.right).abs() <= kHandoffTolerance) {
      continue;
    }
    final what = covered.map((mark) => mark.label).join('、');
    final diff = real.width - bar.width;
    final (kind, verdict) = diff.abs() <= kHandoffTolerance
        ? ('shifted', '一樣長但位置差 ${(real.left - bar.left).toStringAsFixed(1)}')
        : diff > 0
        ? ('short', '骨架短了 ${diff.toStringAsFixed(1)}')
        : ('long', '骨架長了 ${(-diff).toStringAsFixed(1)}');
    out.add(
      HandoffProblem(
        kind,
        '$what：骨架 ${span(bar)}，換上來 ${span(real)}，$verdict',
        bar: bar,
        real: real,
      ),
    );
  }
  for (final mark in content) {
    if (used.contains(mark)) continue;
    out.add(
      HandoffProblem(
        'missing',
        '${mark.label}：沒有骨架（${span(mark.rect)}）',
        real: mark.rect,
      ),
    );
  }
  return out;
}

Element _parentOf(Element element) {
  late Element parent;
  element.visitAncestorElements((ancestor) {
    parent = ancestor;
    return false;
  });
  return parent;
}

Rect _rectOf(Element element) {
  final box = element.renderObject;
  return box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : Rect.zero;
}

/// 這處換場在哪：最近的頁面（型別名稱以 Page 結尾），加上在畫面上的範圍。
String _placeOf(Element element) {
  String? page;
  element.visitAncestorElements((ancestor) {
    final name = ancestor.widget.runtimeType.toString();
    if (name.endsWith('Page')) {
      page = name;
      return false;
    }
    return true;
  });
  final rect = _rectOf(element);
  return '${page ?? '畫面'} 的骨架換場'
      '（y ${rect.top.toStringAsFixed(0)}–${rect.bottom.toStringAsFixed(0)}）';
}

Element? _contentLayerUnder(Element parent) {
  Element? found;
  parent.visitChildElements((child) {
    if (child.widget case SkeletonRevealLayer(
      side: SkeletonRevealSide.content,
    )) {
      found = child;
    }
  });
  return found;
}

Finder _exactly(Element element) =>
    find.byElementPredicate((e) => identical(e, element));

/// 骨架層畫的每一條：[SkeletonBox] 各一條，[SkeletonShapes] 照它畫的字條與
/// 色塊（分組卡片的底不算，那是 `skeleton_match.dart` 管的）。寬度是 0 的
/// 不算：畫面上看不到。
List<Rect> _barsUnder(WidgetTester tester, Element layer) {
  final bars = <Rect>[];
  for (final box
      in find
          .descendant(of: _exactly(layer), matching: find.byType(SkeletonBox))
          .evaluate()) {
    final rect = tester.getRect(_exactly(box));
    if (rect.width > kHandoffTolerance) bars.add(rect);
  }
  for (final shapes
      in find
          .descendant(
            of: _exactly(layer),
            matching: find.byType(SkeletonShapes),
          )
          .evaluate()) {
    bars.addAll(
      skeletonLayoutOf(
        tester,
        _exactly(shapes),
      ).marks.where((rect) => rect.width > kHandoffTolerance),
    );
  }
  return bars;
}

/// 內容層裡看得到的每一塊（同 [contentLayoutOf]），字的那幾塊標上是哪段字。
List<HandoffMark> _marksUnder(WidgetTester tester, Element layer) {
  final rects = contentLayoutOf(tester, _exactly(layer)).marks;
  final paragraphs = <(Rect, String)>[];
  void collect(RenderObject object) {
    if (object is RenderParagraph && object.hasSize) {
      paragraphs.add((
        MatrixUtils.transformRect(
          object.getTransformTo(null),
          Offset.zero & object.size,
        ),
        object.text.toPlainText(includeSemanticsLabels: false),
      ));
    }
    object.visitChildren(collect);
  }

  layer.renderObject!.visitChildren(collect);
  String? textAt(Rect rect) {
    for (final (bounds, text) in paragraphs) {
      if (!bounds.inflate(kHandoffTolerance).contains(rect.center)) continue;
      // 圖示是私用區（含第 15、16 平面）的一個字，不是讀者看得到的字。
      final isIcon = text.runes.every(
        (r) => r >= 0xE000 && r <= 0xF8FF || r >= 0xF0000,
      );
      return isIcon ? null : text;
    }
    return null;
  }

  return [for (final rect in rects) HandoffMark(rect, textAt(rect))];
}

bool _sameBars(List<Rect> a, List<Rect> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if ((x.left - y.left).abs() > kHandoffTolerance ||
        (x.right - y.right).abs() > kHandoffTolerance ||
        (x.top - y.top).abs() > kHandoffTolerance ||
        (x.bottom - y.bottom).abs() > kHandoffTolerance) {
      return false;
    }
  }
  return true;
}

/// 手機回報電量：真的手機在閱讀器訂閱後才送第一筆，訂閱前 `latestBattery`
/// 是空的。
void mockBattery({int percent = 82, bool charging = false}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
        const EventChannel('night_reader/battery'),
        MockStreamHandler.inline(
          onListen: (arguments, events) =>
              events.success({'percent': percent, 'charging': charging}),
        ),
      );
}
