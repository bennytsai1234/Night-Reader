import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';

/// 換掉 Android 那一半，看系統實際收到什麼。只驗 Dart 這邊的協定；
/// 前景服務與通知本身（`BackgroundWorkService.kt`）在這裡跑不到。
class _FakePlatform implements BackgroundWorkPlatform {
  final List<String> calls = [];
  void Function(String action)? handler;

  @override
  Future<bool> show(BackgroundWorkStatus status) async {
    calls.add('show ${status.title}｜${status.text}｜${status.permille}');
    return true;
  }

  @override
  Future<void> hide() async => calls.add('hide');

  @override
  set onAction(void Function(String action)? value) => handler = value;
}

class _Job implements BackgroundJob {
  int stops = 0;
  int opens = 0;

  @override
  void stopFromSystem() => stops++;

  @override
  void openFromNotification() => opens++;
}

const _start = BackgroundWorkStatus(
  title: '校驗書源',
  text: '第 0／4 個',
  progress: 0,
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakePlatform platform;
  late BackgroundWork work;
  late int permissionAsks;

  setUp(() {
    platform = _FakePlatform();
    permissionAsks = 0;
    work = BackgroundWork(
      platform: platform,
      requestPermission: () async => permissionAsks++,
    );
  });

  test('one job at a time: a second one is refused until the first ends', () {
    final first = _Job();
    final second = _Job();

    expect(work.begin(first, _start), isTrue);
    expect(work.isBusy, isTrue);
    expect(work.begin(second, _start), isFalse);
    expect(work.current, same(first));

    work.end(first);
    expect(work.isBusy, isFalse);
    expect(work.begin(second, _start), isTrue);
  });

  test('the notification is updated only when what it shows changes', () async {
    final job = _Job();
    work.begin(job, _start);
    await _flush();
    work.update(job, _start);
    // 同一個千分位：進度條畫不出差別，不重送。
    work.update(
      job,
      const BackgroundWorkStatus(
        title: '校驗書源',
        text: '第 0／4 個',
        progress: 0.0001,
      ),
    );
    await _flush();
    work.update(
      job,
      const BackgroundWorkStatus(
        title: '校驗書源',
        text: '第 1／4 個',
        progress: 0.25,
      ),
    );
    await _flush();
    work.end(job);
    await _flush();

    expect(platform.calls, [
      'show 校驗書源｜第 0／4 個｜0',
      'show 校驗書源｜第 1／4 個｜250',
      'hide',
    ]);
  });

  test('changes made before the last one was sent go out as one', () async {
    final job = _Job();
    work.begin(job, _start);
    for (var done = 1; done <= 3; done++) {
      work.update(
        job,
        BackgroundWorkStatus(
          title: '校驗書源',
          text: '第 $done／4 個',
          progress: done / 4,
        ),
      );
    }
    await _flush();

    expect(platform.calls, ['show 校驗書源｜第 3／4 個｜750']);
  });

  test('an update that arrives after the job ended does not bring the '
      'notification back', () async {
    final job = _Job();
    work.begin(job, _start);
    await _flush();
    work.end(job);
    work.update(
      job,
      const BackgroundWorkStatus(title: '校驗書源', text: '第 4／4 個', progress: 1),
    );
    await _flush();

    expect(platform.calls, ['show 校驗書源｜第 0／4 個｜0', 'hide']);
  });

  test('a job without a known total has no progress bar', () async {
    final job = _Job();
    work.begin(
      job,
      const BackgroundWorkStatus(title: 'AI 修復 · 筆趣閣', text: '第 3 輪'),
    );
    await _flush();

    expect(platform.calls, ['show AI 修復 · 筆趣閣｜第 3 輪｜null']);
  });

  test('notification permission is asked before the first job only', () async {
    final first = _Job();
    work.begin(first, _start);
    await _flush();
    work.end(first);
    work.begin(_Job(), _start);
    await _flush();

    expect(permissionAsks, 1);
  });

  test('stop and a tap on the notification go to the running job', () {
    final job = _Job();
    work.begin(job, _start);

    platform.handler!('stop');
    platform.handler!('open');
    expect(job.stops, 1);
    expect(job.opens, 1);

    work.end(job);
    platform.handler!('stop');
    expect(job.stops, 1, reason: '做完了，晚到的停止不送');
  });

  test('without a platform (iPhone, tests on a computer) nothing is sent but '
      'the slot still works', () {
    final quiet = BackgroundWork(platform: null);
    final job = _Job();
    expect(quiet.begin(job, _start), isTrue);
    expect(quiet.isBusy, isTrue);
    quiet.end(job);
    expect(quiet.isBusy, isFalse);
  });
}
