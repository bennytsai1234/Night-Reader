// 臨時：開 App 呼吸中第 65 格前那 14.6ms 是哪一段程式。把每個計時器與
// 非同步回呼包起來計時，超過 3ms 的印出排它的那幾行 App 程式。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:provider/provider.dart';

import '../../support/screenshot.dart';
import 'survey_support.dart';

bool _entranceFinished() {
  final shelf = find.byType(BookshelfPage).evaluate();
  if (shelf.isEmpty) return false;
  return LaunchEntrance.maybeOf(shelf.first)?.isFinished ?? false;
}

var _frame = -1;
var _probe = WeakReference(Object());
final _old = List<Object?>.generate(400, (_) => Object());
final _oldWeaks = <int, WeakReference<Object>>{};
var _armed = false;

String _where(StackTrace stack) => stack
    .toString()
    .split('\n')
    .where((l) => l.contains('package:night_reader/'))
    .take(4)
    .map((l) => l.replaceAll(RegExp(r'^#\d+\s+'), '      '))
    .join('\n');

void _report(String kind, int micros, StackTrace created) {
  if (!_armed || micros < 3000) return;
  // ignore: avoid_print
  print(
    'PROBE 第$_frame格 '
    '$kind ${(micros / 1000).toStringAsFixed(1)}ms\n${_where(created)}',
  );
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('probe: launch', (tester) async {
    final spec = ZoneSpecification(
      createTimer: (self, parent, zone, duration, f) {
        final created = StackTrace.current;
        return parent.createTimer(zone, duration, () {
          final t = Stopwatch()..start();
          f();
          _report(
            '計時器(${duration.inMilliseconds}ms)',
            t.elapsedMicroseconds,
            created,
          );
        });
      },
      scheduleMicrotask: (self, parent, zone, f) {
        final created = StackTrace.current;
        parent.scheduleMicrotask(zone, () {
          final t = Stopwatch()..start();
          f();
          _report('非同步回呼', t.elapsedMicroseconds, created);
        });
      },
    );
    await runZoned(
      () => runSurvey(
        tester,
        launch: () => surveyStep(
          tester,
          area: 'probe',
          key: 'probe01',
          label: '開 App',
          action: () async {
            _armed = !_armedOnce;
            _armedOnce = true;
            _frame = -1;
            await tester.pumpWidget(
              MultiProvider(
                providers: AppProviders.providers,
                child: const ReaderApp(),
              ),
            );
          },
          until: _entranceFinished,
          onFrame: (i) async {
            // 探針：沒人引用的物件被清掉，代表上一格到這一格之間回收過一次。
            if (_armed && _probe.target == null) {
              // ignore: avoid_print
              print('GC 第${i - 1}格到第$i格之間回收了一次');
            }
            _probe = WeakReference(Object());
            // 老物件探針：開頭就建好、撐過暖身早已搬進老年區的物件，每格放掉
            // 一個；它被清掉代表這段時間跑過一次清老年區的大回收。
            if (_armed) {
              for (final entry in _oldWeaks.entries.toList()) {
                if (entry.value.target == null) {
                  // ignore: avoid_print
                  print('OLDGC 第$i格開頭前清掉了第${entry.key}格放掉的老物件');
                  _oldWeaks.remove(entry.key);
                }
              }
              if (i < _old.length) {
                _oldWeaks[i] = WeakReference(_old[i]!);
                _old[i] = null;
              }
            }
            _frame = i;
          },
        ),
        steps: () async {},
      ),
      zoneSpecification: spec,
    );
  });
}

// 第一次（暖身）不印，第二次（正式量）才印。
var _armedOnce = false;
