import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:night_reader/features/comic_reader/comic_page_images.dart';
import 'package:night_reader/features/comic_reader/comic_page_source.dart';

import 'comic_test_pages.dart';

/// 每張圖都要等測試放行（[release]）才回，記著要了哪幾張、照什麼順序。
class _GatedSource implements ComicPageSource {
  final List<String> requested = [];
  final Map<String, Completer<Uint8List>> _pending = {};
  final Set<String> failing = {};
  final Uint8List _png = stripedPng(20, 40, 0x336699, 0x112233);

  @override
  Future<List<ComicPage>> pagesOf(int chapterIndex) async => const [];

  @override
  Future<Uint8List> bytesOf(int chapterIndex, ComicPage page) {
    requested.add(page.name);
    return (_pending[page.name] = Completer<Uint8List>()).future;
  }

  void release(String name) {
    final completer = _pending.remove(name)!;
    if (failing.contains(name)) {
      completer.completeError(StateError('抓不到 $name'));
    } else {
      completer.complete(_png);
    }
  }

  @override
  String? webUrlOf(int chapterIndex, ComicPage page) => null;
}

ComicImageKey _key(String name) => ComicImageKey(0, ComicPage(name: name), 20);

/// 解碼在引擎的執行緒，等真的時間。
Future<void> _settle(WidgetTester tester) => tester.runAsync(
  () => Future<void>.delayed(const Duration(milliseconds: 50)),
);

void main() {
  testWidgets('照範圍的順序讀，同時最多幾張；範圍外的放掉', (tester) async {
    final source = _GatedSource();
    final sizes = <ComicImageKey>[];
    final images = ComicPageImages(
      source: source,
      concurrency: 2,
      onSize: (key, _) => sizes.add(key),
    );
    images.demand([_key('a'), _key('b'), _key('c')]);
    expect(source.requested, ['a', 'b']);

    source.release('a');
    await _settle(tester);
    expect(source.requested, ['a', 'b', 'c']);
    final image = images.image(_key('a'));
    expect(image, isNotNull);
    image!.dispose();
    expect(sizes, [_key('a')]);
    expect(images.heldBytes, 20 * 40 * 4);

    // 範圍移走：a 放掉；還在讀的 b 讀完也不留。
    images.demand([_key('c')]);
    expect(images.image(_key('a')), isNull);
    expect(images.heldBytes, 0);
    source.release('b');
    source.release('c');
    await _settle(tester);
    expect(images.image(_key('b')), isNull);
    images.image(_key('c'))!.dispose();
    expect(images.peakBytes, 20 * 40 * 4);
    images.dispose();
  });

  testWidgets('畫面上的不等位置、馬上開始；畫面外要畫的排最前面；在畫的離開範圍也留著', (tester) async {
    final source = _GatedSource();
    final images = ComicPageImages(source: source, concurrency: 3);
    var notified = 0;
    void listener() => notified += 1;
    void other() {}
    images.demand([_key('a'), _key('b'), _key('c'), _key('d'), _key('e')]);
    expect(source.requested, ['a', 'b', 'c']);
    // 畫面外已經建好、要畫的 d：排最前面，但三個位置都佔著，先等。
    images.addListener(_key('d'), other);
    images.want(_key('d'));
    expect(source.requested, ['a', 'b', 'c']);
    // 捲到 e、e 在畫面上：不排在 d 後面，馬上開始。
    images.addListener(_key('e'), listener);
    images.demand([
      _key('e'),
      _key('a'),
      _key('b'),
      _key('c'),
      _key('d'),
    ], visibleCount: 1);
    images.want(_key('e'));
    expect(source.requested, ['a', 'b', 'c', 'e']);
    source.release('e');
    await _settle(tester);
    expect(notified, 1);
    for (final name in ['a', 'b', 'c']) {
      source.release(name);
    }
    await _settle(tester);
    expect(source.requested, ['a', 'b', 'c', 'e', 'd']);
    source.release('d');
    await _settle(tester);
    for (final name in ['a', 'b', 'c', 'd']) {
      images.image(_key(name))!.dispose();
    }
    // 範圍移走：沒有人在畫的放掉，在畫的留著，畫完才放。
    images.demand(const []);
    expect(images.image(_key('a')), isNull);
    final image = images.image(_key('e'));
    expect(image, isNotNull);
    image!.dispose();
    images.removeListener(_key('e'), listener);
    images.removeListener(_key('d'), other);
    expect(images.image(_key('e')), isNull);
    expect(images.image(_key('d')), isNull);
    images.dispose();
  });

  testWidgets('畫面外載不到的不記成失敗、不再預載；捲進畫面時再試一次', (tester) async {
    final source = _GatedSource()..failing.add('a');
    final images = ComicPageImages(source: source);
    var notified = 0;
    void listener() => notified += 1;
    images.demand([_key('a')]);
    // 畫面外已經建好、在畫的元件：失敗也不提早顯示。
    images.addListener(_key('a'), listener);
    images.want(_key('a'));
    source.release('a');
    await _settle(tester);
    expect(images.error(_key('a')), isNull);
    images.demand([_key('a')]);
    images.want(_key('a'));
    expect(source.requested, ['a']);

    // 捲進畫面：再試一次，這次失敗就記著，給「重試」。
    images.demand([_key('a')], visibleCount: 1);
    expect(source.requested, ['a', 'a']);
    source.release('a');
    await _settle(tester);
    expect(images.error(_key('a')), isA<StateError>());
    expect(notified, 2);
    // 一直在畫面上：不再自己試。
    images.demand([_key('a')], visibleCount: 1);
    images.want(_key('a'));
    expect(source.requested, ['a', 'a']);

    source.failing.clear();
    images.retry(_key('a'));
    expect(source.requested, ['a', 'a', 'a']);
    source.release('a');
    await _settle(tester);
    expect(images.error(_key('a')), isNull);
    images.image(_key('a'))!.dispose();
    images.removeListener(_key('a'), listener);
    images.dispose();
  });

  testWidgets('在畫面上、還沒有元件在畫時載不到：元件建好時再試一次', (tester) async {
    final source = _GatedSource()..failing.add('a');
    final images = ComicPageImages(source: source);
    images.demand([_key('a')], visibleCount: 1);
    source.release('a');
    await _settle(tester);
    // 沒有元件回報失敗高度，不記成失敗。
    expect(images.error(_key('a')), isNull);
    images.demand([_key('a')], visibleCount: 1);
    expect(source.requested, ['a']);

    void listener() {}
    images.addListener(_key('a'), listener);
    images.want(_key('a'));
    expect(source.requested, ['a', 'a']);
    source.release('a');
    await _settle(tester);
    expect(images.error(_key('a')), isA<StateError>());
    images.removeListener(_key('a'), listener);
    images.dispose();
  });
}
