from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def edit(path: str, fn) -> None:
    p = ROOT / path
    old = p.read_text(encoding='utf-8')
    new = fn(old)
    if new == old:
        raise RuntimeError(f'{path}: cleanup made no change')
    p.write_text(new, encoding='utf-8')


def sub1(text: str, pattern: str, repl: str, label: str) -> str:
    out, count = re.subn(pattern, repl, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, got {count}')
    return out


# Leftover restore barrier local from the old page-distance materialization path.
edit(
    'lib/features/reader_v2/hybrid/hybrid_reader_screen.dart',
    lambda s: s.replace(
        '      final restoreOnly = _restorePrefetchBarrierActive;\n',
        '',
        1,
    ),
)

# Admission no longer has a viewport-gated edge policy, so this private helper
# has no owner and should not survive as dead architecture.
def clean_admission(s: str) -> str:
    return sub1(
        s,
        r'\n  bool _isContiguousEdge\(BlockKey key\) \{\n    return key < documentIndex\.centerKey\n        \? _nextBackwardKey\(\) == key\n        : _nextForwardKey\(\) == key;\n  \}\n',
        '\n',
        'remove obsolete contiguous-edge helper',
    )

edit('lib/features/reader_v2/hybrid/view/admission_controller.dart', clean_admission)

# Paragraph cache no longer has waiter/pinning semantics. Remove the last local
# bookkeeping remnant left by the old waiter implementation.
def clean_cache(s: str) -> str:
    s = s.replace('    final touchedWaiterKeys = <_ParagraphCacheKey>[];\n', '', 1)
    s = s.replace('      touchedWaiterKeys.add(cacheKey);\n', '', 1)
    s = s.replace(
        '/// Paragraph 裡自己的 Y 窗起點（非 group 或 group 頭塊為 0）。\n/// paint 熱路徑以色相等與否決定「直繪」或「過渡 tint」。',
        '/// Paragraph 裡自己的 Y 窗起點（非 group 或 group 頭塊為 0）。\n/// 條目在目前 layout epoch 內保留；cache miss 不再是可等待的 render state。',
    )
    return s

edit('lib/features/reader_v2/hybrid/paragraph/paragraph_cache.dart', clean_cache)

# Old tests encoded the deleted LRU pin/wait readiness system. Replace them with
# the new contract: entries remain valid for the epoch and explicit semantic
# invalidation is the only thing that removes them.
def clean_pump_tests(s: str) -> str:
    prefix_pattern = (
        r"  group\('ParagraphCache', \(\) \{\n"
        r"[\s\S]*?"
        r"    test\('tracks baked color for the paint fast path', \(\) \{"
    )
    prefix_repl = """  group('ParagraphCache', () {
    test('keeps laid-out paragraphs available for the layout epoch', () {
      final cache = ParagraphCache(capacity: 1);
      const epoch = LayoutEpoch.initial;
      const key0 = BlockKey(chapterIndex: 0, blockIndex: 0);
      const key1 = BlockKey(chapterIndex: 0, blockIndex: 1);
      const key2 = BlockKey(chapterIndex: 0, blockIndex: 2);

      cache
        ..put(key0, epoch, _paragraph('a'))
        ..put(key1, epoch, _paragraph('b'))
        ..put(key2, epoch, _paragraph('c'));

      expect(cache.contains(key0, epoch), isTrue);
      expect(cache.contains(key1, epoch), isTrue);
      expect(cache.contains(key2, epoch), isTrue);
      cache.dispose();
    });

    test('semantic invalidation removes only the invalidated chapter', () {
      final cache = ParagraphCache();
      const epoch = LayoutEpoch.initial;
      const chapter0 = BlockKey(chapterIndex: 0, blockIndex: 0);
      const chapter1 = BlockKey(chapterIndex: 1, blockIndex: 0);

      cache
        ..put(chapter0, epoch, _paragraph('a'))
        ..put(chapter1, epoch, _paragraph('b'))
        ..invalidateChapter(0);

      expect(cache.contains(chapter0, epoch), isFalse);
      expect(cache.contains(chapter1, epoch), isTrue);
      cache.dispose();
    });

    test('tracks baked color for the paint fast path', () {"""
    s = sub1(s, prefix_pattern, prefix_repl, 'replace paragraph readiness tests')

    drag_pattern = (
        r"    test\('asserts instead of laying out while dragging', \(\) async \{"
        r"[\s\S]*?"
        r"      cache\.dispose\(\);\n"
        r"    \}\);"
    )
    drag_repl = """    test('continues laying out while dragging', () async {
      final store = MeasurementStore();
      final cache = ParagraphCache();
      final namespace = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: _fingerprint(),
      );
      final pump = LayoutPump(
        paragraphCache: cache,
        measurementStore: store,
        namespace: namespace,
      )..onScrollStateChanged(PumpState.dragging);
      const key = BlockKey(chapterIndex: 0, blockIndex: 0);
      pump.submit(
        LayoutTask(
          block: const ChapterBlock(
            key: key,
            text: 'drag layout',
            charRange: HybridTextRange(0, 11),
            sourceParagraphIndex: 0,
          ),
          epoch: namespace.epoch,
          fingerprint: namespace.fingerprint,
          textStyle: const HybridBlockTextStyle(
            fontSize: 18,
            lineHeight: 1.5,
            letterSpacing: 0,
          ),
          contentWidth: 240,
        ),
      );

      expect(await pump.pumpPending(), 1);
      expect(store.get(namespace, key), isNotNull);
      expect(cache.contains(key, namespace.epoch), isTrue);
      pump.dispose();
      cache.dispose();
    });"""
    return sub1(s, drag_pattern, drag_repl, 'replace dragging stop test')

edit('test/features/reader_v2/hybrid/hybrid_pump_test.dart', clean_pump_tests)

print('direct-flow cleanup applied')
