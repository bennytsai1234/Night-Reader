// 臨時：開 App 呼吸中第 65 格「幀前」那 17ms 是誰。(1) 換一個測試 binding，
// 把每個排進下一幀的回呼（ticker 的 tick）包起來計時；(2) 把每個計時器與
// 非同步回呼包起來，按「排它的 App 程式」逐格加總。印出一格加總超過 5ms
// 的來源，以及每格 pump 裡 binding 開始畫之前（elapse）花的時間。
import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

var _frame = 0;
var _armed = false;
final _origins = <Object, String>{};

/// 這一格裡各來源加總的微秒數與次數。
var _sums = <String, (int, int)>{};
var _beginAt = 0;
final _clock = Stopwatch()..start();
var _pumpStart = 0;

String _where(StackTrace stack) {
  final lines = stack
      .toString()
      .split('\n')
      .where((l) => l.contains('package:night_reader/'))
      .take(3)
      .map((l) => l.replaceAll(RegExp(r'^#\d+\s+'), '      '))
      .join('\n');
  return lines.isEmpty ? '      （沒有 App 程式，框架或套件自己排的）' : lines;
}

void _add(String kind, String origin, int us) {
  if (!_armed) return;
  final key = '$kind\n$origin';
  final (sum, count) = _sums[key] ?? (0, 0);
  _sums[key] = (sum + us, count + 1);
}

class _ProbeBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
    bool scheduleNewFrame = true,
  }) {
    final origin = _origins[callback] ??= _where(StackTrace.current);
    return super.scheduleFrameCallback(
      (timeStamp) {
        final t = Stopwatch()..start();
        callback(timeStamp);
        _add('tick', origin, t.elapsedMicroseconds);
      },
      rescheduling: rescheduling,
      scheduleNewFrame: scheduleNewFrame,
    );
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _beginAt = _clock.elapsedMicroseconds;
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  Future<void> pump([
    Duration? duration,
    EnginePhase newPhase = EnginePhase.sendSemanticsUpdate,
  ]) {
    _pumpStart = _clock.elapsedMicroseconds;
    _beginAt = -1;
    return super.pump(duration, newPhase);
  }
}

bool _entranceFinished() {
  final shelf = find.byType(BookshelfPage).evaluate();
  if (shelf.isEmpty) return false;
  return LaunchEntrance.maybeOf(shelf.first)?.isFinished ?? false;
}

void main() {
  _ProbeBinding();
  // 每一格畫完：印出這一格 pump 開始到 binding 開始畫之前的時間，以及加總
  // 超過 5ms 的來源。
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    if (_armed) {
      final elapse = _beginAt < 0 ? -1 : _beginAt - _pumpStart;
      final total = _sums.values.fold(0, (a, b) => a + b.$1);
      if (elapse > 5000 || total > 5000) {
        // ignore: avoid_print
        print(
          'TICK 第$_frame次畫面：開始畫之前 ${(elapse / 1000).toStringAsFixed(1)}ms，'
          '回呼加總 ${(total / 1000).toStringAsFixed(1)}ms',
        );
        final top = _sums.entries.toList()
          ..sort((a, b) => b.value.$1.compareTo(a.value.$1));
        for (final e in top.take(4)) {
          // ignore: avoid_print
          print(
            '  ${(e.value.$1 / 1000).toStringAsFixed(1)}ms ×${e.value.$2} ${e.key}',
          );
        }
      }
    }
    _sums = {};
    _frame++;
  });
  setUpAll(loadScreenshotFonts);

  testWidgets('probe: launch ticks', (tester) async {
    final spec = ZoneSpecification(
      createTimer: (self, parent, zone, duration, f) {
        final created = _where(StackTrace.current);
        return parent.createTimer(zone, duration, () {
          final t = Stopwatch()..start();
          f();
          _add(
            '計時器(${duration.inMilliseconds}ms)',
            created,
            t.elapsedMicroseconds,
          );
        });
      },
      scheduleMicrotask: (self, parent, zone, f) {
        final created = _where(StackTrace.current);
        parent.scheduleMicrotask(zone, () {
          final t = Stopwatch()..start();
          f();
          _add('非同步回呼', created, t.elapsedMicroseconds);
        });
      },
    );
    var launches = 0;
    await runZoned(
      () => runSurvey(
        tester,
        launch: () async {
          // 只看正式量的那一次（第二次開 App）。
          _armed = ++launches == 2;
          // 實驗：PROBE_PAUSE=1 時正式量之前把暖身留下的下載全部暫停，看
          // 第 65 格的尖峰是不是它。
          if (_armed && Platform.environment['PROBE_PAUSE'] == '1') {
            final service = DownloadService();
            for (final task in [...service.tasks]) {
              service.pauseTask(task.bookUrl);
            }
            await settle(tester, const Duration(seconds: 2));
          }
          // ignore: avoid_print
          print('TICK 開 App（第$launches次）從第$_frame次畫面開始');
          await surveyStep(
            tester,
            area: 'probe',
            key: 'tick01',
            label: '開 App',
            action: () => tester.pumpWidget(
              MultiProvider(
                providers: AppProviders.providers,
                child: const ReaderApp(),
              ),
            ),
            until: _entranceFinished,
          );
          _armed = false;
        },
        steps: () async {},
      ),
      zoneSpecification: spec,
    );
  });
}
