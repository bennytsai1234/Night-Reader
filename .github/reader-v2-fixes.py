"""Follow-up source edits; temporary delivery file, removed before final delivery."""
from pathlib import Path
root = Path.cwd()
p = root / 'lib/features/reader_v2/session/reader_v2_navigation_controller.dart'
s = p.read_text().replace("import 'reader_v2_state.dart';\n", '')
a = s.index('  Future<void> jumpToLocation(')
b = s.index('  Future<bool> restoreFromLocation(', a)
chunk = s[a:b]
x = chunk.index('      _retainLayoutsForWindow(window);')
y = chunk.index('    } catch (e) {', x)
chunk = chunk[:x] + '''      _retainLayoutsForWindow(window);
      var visibleLocation = resolvedLocation;
      final restore = _runtime.viewportBridge.viewportRestore;
      if (restore != null) {
        // Navigation owns positioning. Persistence never starts a second
        // restore after this operation has already announced ready.
        _runtime.updatePageWindow(window);
        final positioned = await restore(resolvedLocation);
        if (!_isCurrentOperation(token)) return;
        if (!positioned) {
          _runtime.failOperation(token, StateError('Viewport restore failed.'));
          return;
        }
        if (!_isTopAlignedChapterStart(resolvedLocation)) {
          visibleLocation = _runtime.viewportBridge.captureVisibleLocation(
            allowDuringRestore: true,
          ) ?? resolvedLocation;
        }
      }
      if (!_runtime.completeReadyOperation(
        token,
        visibleLocation: visibleLocation,
        pageWindow: window,
      )) return;
      unawaited(
        _runtime.preloadScheduler.scheduleJump(visibleLocation.chapterIndex),
      );
      if (immediateSave) {
        await _runtime.viewportBridge.saveProgressLocation(visibleLocation);
      }
''' + chunk[y:]
s = s[:a] + chunk + s[b:]
p.write_text(s)
p = root / 'lib/features/reader_v2/session/reader_v2_viewport_bridge.dart'
s = p.read_text()
for imp in ["import 'dart:async';\n\n", "import 'package:flutter/widgets.dart';\n\n", "import 'reader_v2_operation_token.dart';\n"]:
    s = s.replace(imp, '')
a = s.index('  Future<ReaderV2Location?> saveJumpAfterSettled(')
b = s.index('  Future<ReaderV2Location?> saveProgressLocation(', a)
s = s[:a] + s[b:]
a = s.index('  Future<ReaderV2Location?> _saveVisibleAnchorAfterViewportSettled(')
b = s.index('  Future<ReaderV2Location?> _saveProgressLocation(', a)
s = s[:a] + s[b:]
p.write_text(s)
p = root / 'test/features/reader_v2/reader_v2_navigation_viewport_bridge_test.dart'
s = p.read_text()
if "import 'dart:async';" not in s:
    s = "import 'dart:async';\n\n" + s
idx = s.index("  group('ReaderV2 navigation and viewport boundaries', () {")
idx = s.index('\n',idx)+1
s=s[:idx]+'''    test('navigation positions once before publishing ready and saving', () async {
      final harness = _makeRuntime();
      final runtime = harness.runtime;
      addTearDown(runtime.dispose);
      await runtime.openBook();
      final entered = Completer<void>();
      final positioned = Completer<bool>();
      var restoreCalls = 0;
      runtime.registerViewportRestore(Object(), (location) {
        restoreCalls += 1;
        expect(location.chapterIndex, 1);
        entered.complete();
        return positioned.future;
      });
      final jump = runtime.jumpToChapter(1);
      await entered.future;
      expect(runtime.state.phase, ReaderV2Phase.layingOut);
      expect(runtime.state.visibleLocation.chapterIndex, 0);
      expect(harness.bookDao.savedLocations, isEmpty);
      positioned.complete(true);
      await jump;
      expect(runtime.state.phase, ReaderV2Phase.ready);
      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expect(harness.bookDao.savedLocations.single.chapterIndex, 1);
      await runtime.saveProgress(
        location: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      );
      expect(restoreCalls, 1);
      expect(runtime.state.visibleLocation.chapterIndex, 1);
    });

'''+s[idx:]
p.write_text(s)
p = root / 'integration_test/reader_journey_test.dart'
s = p.read_text().replace('  IntegrationTestWidgetsFlutterBinding.ensureInitialized();', '  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();')
s = s.replace('      await reader.reopen(location);', '''      await reader.reopen(location);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('reader-after-reopen');''')
p.write_text(s)
