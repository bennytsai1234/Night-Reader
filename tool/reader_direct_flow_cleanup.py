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


def sub1(text: str, pattern: str, repl: str, label: str, flags=re.MULTILINE) -> str:
    out, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, got {count}')
    return out


# The paragraph cache is epoch-owned storage, not a bounded readiness cache.
def clean_contracts(s: str) -> str:
    s = s.replace('  void pinRange(BlockRange range);\n', '', 1)
    s = s.replace('  void unpinAll();\n', '', 1)
    return s

edit('lib/features/reader_v2/hybrid/core/hybrid_contracts.dart', clean_contracts)


def clean_cache(s: str) -> str:
    s = s.replace(
        '  ParagraphCache({this.capacity = 512}) : assert(capacity > 0);\n\n  final int capacity;\n',
        '  ParagraphCache();\n',
        1,
    )
    s = sub1(
        s,
        r'\n  @override\n  void pinRange\(BlockRange range\) \{\}\n\n  void pinKeys\(Iterable<BlockKey> keys, LayoutEpoch epoch\) \{\}\n\n  @override\n  void unpinAll\(\) \{\}\n\n  void trimToCapacity\(\) \{\}\n',
        '\n',
        'remove paragraph compatibility methods',
    )
    return s

edit('lib/features/reader_v2/hybrid/paragraph/paragraph_cache.dart', clean_cache)


# No scroll/readiness friction surface remains in AdmissionController.
def clean_admission(s: str) -> str:
    s = s.replace('  bool get hasLeadDeficit => false;\n\n', '', 1)
    s = s.replace(
        '  double frictionScaleToward({required bool forward}) => 0.0;\n\n',
        '',
        1,
    )
    return s

edit('lib/features/reader_v2/hybrid/view/admission_controller.dart', clean_admission)


# Interaction never pauses layout. Remove the no-op API rather than preserving
# a name that invites the old architecture back in.
def clean_scheduler(s: str) -> str:
    block = '''  bool get isInteractive => false;\n\n  int get debugInteractiveDepth => 0;\n\n  void beginInteractive() {}\n\n  void endInteractive() {}\n\n'''
    if block not in s:
        raise RuntimeError('scheduler interactive compatibility block missing')
    return s.replace(block, '', 1)

edit('lib/features/reader_v2/session/reader_v2_preload_scheduler.dart', clean_scheduler)


def clean_navigation(s: str) -> str:
    block = '''  void beginInteractivePreloadPause() {\n    if (_runtime.disposed) return;\n    _runtime.preloadScheduler.beginInteractive();\n  }\n\n  void endInteractivePreloadPause() {\n    if (_runtime.disposed) return;\n    _runtime.preloadScheduler.endInteractive();\n  }\n\n  bool get debugIsPreloadLayoutPaused =>\n      _runtime.preloadScheduler.isInteractive;\n\n'''
    if block not in s:
        raise RuntimeError('navigation interactive-pause block missing')
    return s.replace(block, '', 1)

edit('lib/features/reader_v2/session/reader_v2_navigation_controller.dart', clean_navigation)


def clean_runtime(s: str) -> str:
    block = '''  void beginInteractivePreloadPause() {\n    navigation.beginInteractivePreloadPause();\n  }\n\n  void endInteractivePreloadPause() {\n    navigation.endInteractivePreloadPause();\n  }\n\n  bool get debugIsPreloadLayoutPaused => navigation.debugIsPreloadLayoutPaused;\n\n'''
    if block not in s:
        raise RuntimeError('runtime interactive-pause block missing')
    return s.replace(block, '', 1)

edit('lib/features/reader_v2/session/reader_v2_runtime.dart', clean_runtime)


# Hybrid screen no longer exposes a cache capacity because there is no LRU
# eviction in the correctness path, and settle no longer has a full-prefetch
# mode. Every settle follows the same direct-flow path.
def clean_screen(s: str) -> str:
    s = s.replace('    this.paragraphCacheCapacity = 512,\n', '', 1)
    s = s.replace('  final int paragraphCacheCapacity;\n', '', 1)
    s = s.replace(
        '    _paragraphCache = ParagraphCache(capacity: widget.paragraphCacheCapacity);',
        '    _paragraphCache = ParagraphCache();',
        1,
    )
    s = s.replace(
        '  Future<void> _handleScrollSettled({bool allowFullPrefetch = false}) async {',
        '  Future<void> _handleScrollSettled() async {',
        1,
    )
    s = s.replace('_handleScrollSettled(allowFullPrefetch: true)', '_handleScrollSettled()')
    return s

edit('lib/features/reader_v2/hybrid/hybrid_reader_screen.dart', clean_screen)


# Align tests with the new API. The old small-capacity fixture existed only to
# force the LRU miss/waiter path that no longer exists.
def clean_screen_test(s: str) -> str:
    s = s.replace('    int paragraphCacheCapacity = 512,\n', '', 1)
    s = s.replace('              paragraphCacheCapacity: paragraphCacheCapacity,\n', '', 1)
    s = s.replace(
        '    await pumpScreen(tester, runtime, controller, paragraphCacheCapacity: 4);',
        '    await pumpScreen(tester, runtime, controller);',
        1,
    )
    return s

edit('test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart', clean_screen_test)


def clean_pump_test(s: str) -> str:
    if 'ParagraphCache(capacity: 1)' not in s:
        raise RuntimeError('expected direct-flow paragraph capacity fixture missing')
    return s.replace('ParagraphCache(capacity: 1)', 'ParagraphCache()', 1)

edit('test/features/reader_v2/hybrid/hybrid_pump_test.dart', clean_pump_test)


# Comments must describe the new invariant, not the removed drag gate.
def clean_layout_pump(s: str) -> str:
    s = s.replace(
        '  /// 丟棄已不在當前需求視窗內的 task。純記帳、不做排版，因此在 dragging\n  /// 期間呼叫也不違反 I4。回傳丟棄數量。',
        '  /// 丟棄已不屬於目前 layout epoch / fingerprint 的 task。純記帳、\n  /// 不做排版；互動狀態不參與 task 是否有效。回傳丟棄數量。',
        1,
    )
    return s

edit('lib/features/reader_v2/hybrid/pump/layout_pump.dart', clean_layout_pump)

print('final direct-flow API cleanup applied')
