// 量動畫期間每一幀主執行緒忙多久（ADR 0018）：宣稱工作已離開主執行緒、
// 或要拿掉一段等待之前，用 test/frame_budget/ 的情境實際量一次。
//
//   flutter test --run-skipped -t frame_budget test/frame_budget
//   FRAME_ATTRIBUTE=1 flutter test --run-skipped -t frame_budget test/frame_budget
//
// 比對改動前後用 `bash tool/frame_budget_compare.sh <改前的提交> <測試檔>`：它把
// 改前開在暫時的 worktree、兩邊交錯各跑幾次，並讓同一台電腦上的量測排隊。
//
// 量到的是電腦上 debug 模式的時間，手機上會慢好幾倍，看的是相對大小與尖峰
// 出現在哪一段。FRAME_ATTRIBUTE=1 時另外列出尖峰幀裡自己耗時最多（扣掉包在
// 裡面的）的 widget 與 render object，以及重建從哪些 widget 開始（誰呼叫了
// setState）；打開這些紀錄本身會讓數字變大（每排一次重建就印一段堆疊，整棵
// 子樹被搬動、一次排上百個重建時會大上幾十倍），只拿來找是誰。測試環境
// 沒有開書源 isolate（`SourceIsolate.enabled`），書源工作在原地執行，會算進
// 主執行緒。
//
//   FRAME_GC=1 flutter test --enable-vmservice …
//   FRAME_CPU=1 flutter test --enable-vmservice …
//
// FRAME_CPU=1 時對動畫中超過上限的幀取 CPU 取樣，列出那一幀裡最花時間的
// 函式（[frameCpu]），查「幀前」這類不在重建裡的工作。
//
// FRAME_GC=1 時另外記下每一幀裡 Dart 回收記憶體幾次、主執行緒因此停住多久：
// 時間已經算在當時那一段裡，這裡標出多出來的是回收。測試是一幀接一幀直接
// 推進，引擎不會在兩幀之間通知 Dart「有空檔」，手機上趁空檔做的回收（#130
// 換場途中那 12～13ms）在這裡不會發生，只有新生區滿了才回收。

import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' hide Isolate, Timeline;
import 'package:vm_service/vm_service_io.dart';

import 'db_clock.dart';
import 'slice_clock.dart';

/// 一幀的成本，單位微秒。
class FrameCost {
  const FrameCost({
    required this.index,
    required this.beforeFrame,
    required this.frame,
    required this.afterFrame,
    required this.async,
    required this.top,
    required this.dirty,
    this.note,
    this.moving = false,
    this.scavenges = 0,
    this.scavengeMicros = 0,
    this.oldCollections = 0,
    this.oldGcMicros = 0,
    this.dbMicros = 0,
    this.sliceMicros = 0,
    this.cpu = const [],
  });

  final int index;

  /// [frameCpu] 開著時，這一幀（動畫中超過上限的）CPU 取樣的摘要。
  final List<String> cpu;

  /// 這一幀開始前的計時器與 microtask（資料工作多半在這裡）。
  final int beforeFrame;

  /// 動畫、build、layout、paint。
  final int frame;

  /// 這一幀之後的 post-frame callback 與 microtask。
  final int afterFrame;

  /// 讓出真實時間給資料庫等 isolate 時，回到主執行緒的後續工作。
  final int async;

  /// [FRAME_ATTRIBUTE] 開著時，這一幀耗時最多的區塊。
  final List<AggregatedTimedBlock> top;

  /// [FRAME_ATTRIBUTE] 開著時，這一幀被標成要重建的 widget（重建從哪裡
  /// 開始，誰呼叫了 setState 或 markNeedsBuild）與次數。
  final Map<String, int> dirty;

  /// 這一幀畫完時畫面在哪一段（[recordFrames] 的 `note`），例如換頁中、
  /// 骨架、換場。
  final String? note;

  /// 這一幀有動畫在走（上一幀結束時排著 ticker，例如換頁、骨架呼吸、換場、
  /// 淡入）：這一幀晚了，畫面上看得到動作頓一下。沒有的是靜止的一幀，晚了
  /// 只是畫面晚一點變（ADR 0031：重活放在畫面靜止的時候）。被一張定格畫面
  /// 蓋住的動畫也算在走（開 App 拍「之後」那一格），看尖峰時對照 [note]。
  final bool moving;

  /// [frameGc] 開著時，這一幀裡回收新生區（新建的物件放的地方，回收時把
  /// 還活著的搬走）幾次、共停住多久。
  final int scavenges;
  final int scavengeMicros;

  /// [frameGc] 開著時，這一幀裡回收舊生區幾次、共停住多久（並行標記與清掃
  /// 在別的執行緒上做，不算）。
  final int oldCollections;
  final int oldGcMicros;

  int get gcMicros => scavengeMicros + oldGcMicros;

  /// 這一幀裡測試的資料庫在主執行緒上花的時間（`db_clock.dart`）。手機上
  /// 資料庫在自己的 isolate，不佔這一幀；只會少算、不會多算。
  final int dbMicros;

  /// 這一幀裡閱讀器排版照時間切的那幾片（`slice_clock.dart`）：每格做到
  /// 預算就停，手機上一樣長，不照 2 倍換算（ADR 0036）。
  final int sliceMicros;

  int get total => beforeFrame + frame + afterFrame + async;

  /// 扣掉測試才有的資料庫時間，手機上這一幀主執行緒的工作（照 2 倍換算前）。
  int get app => total - dbMicros;

  /// 判斷動畫中的幀有沒有超過 [frameLimit] 看這個（ADR 0036）：排版切片照實
  /// 算、其他工作照 2 倍換算到手機，再折回電腦的尺度和 4.2ms 比，也就是
  /// 扣掉資料庫後再扣掉排版切片的一半。
  int get judged => app - sliceMicros ~/ 2;

  FrameCost _withCpu(List<String> lines) => FrameCost(
    index: index,
    beforeFrame: beforeFrame,
    frame: frame,
    afterFrame: afterFrame,
    async: async,
    top: top,
    dirty: dirty,
    note: note,
    moving: moving,
    scavenges: scavenges,
    scavengeMicros: scavengeMicros,
    oldCollections: oldCollections,
    oldGcMicros: oldGcMicros,
    dbMicros: dbMicros,
    sliceMicros: sliceMicros,
    cpu: lines,
  );

  FrameCost _withGc(Iterable<_GcPause> pauses) => FrameCost(
    index: index,
    beforeFrame: beforeFrame,
    frame: frame,
    afterFrame: afterFrame,
    async: async,
    top: top,
    dirty: dirty,
    note: note,
    moving: moving,
    scavenges: pauses.where((p) => p.young).length,
    scavengeMicros: pauses
        .where((p) => p.young)
        .fold(0, (sum, p) => sum + p.micros),
    oldCollections: pauses.where((p) => !p.young).length,
    oldGcMicros: pauses
        .where((p) => !p.young)
        .fold(0, (sum, p) => sum + p.micros),
    dbMicros: dbMicros,
    sliceMicros: sliceMicros,
    cpu: cpu,
  );
}

/// 電腦上動畫中一幀的上限：手機 120Hz 一幀 8.3ms，照 2 倍換算（ADR 0029、0036）。
const Duration frameLimit = Duration(microseconds: 4200);

/// 環境變數 `FRAME_ATTRIBUTE=1` 時列出尖峰幀裡耗時最多的區塊。
final bool frameAttribution = Platform.environment['FRAME_ATTRIBUTE'] == '1';

/// 環境變數 `FRAME_PHASES=1` 時只列尖峰幀各大階段（BUILD、LAYOUT、PAINT、
/// COMPOSITING、SEMANTICS…）各花多久：不開逐個元件的紀錄，數字幾乎不變大，
/// 看得出多出來的時間落在哪一段。
final bool framePhases = Platform.environment['FRAME_PHASES'] == '1';

/// 環境變數 `FRAME_GC=1` 時記下每一幀的記憶體回收（要加 `--enable-vmservice`）。
final bool frameGc = Platform.environment['FRAME_GC'] == '1';

/// 環境變數 `FRAME_CPU=1` 時，對動畫中超過 [frameLimit] 的幀向 VM 取 CPU
/// 取樣，列出那一幀裡自己花時間最多的函式，以及樣本落在 App 程式（`lib/`）
/// 的哪個函式裡（要加 `--enable-vmservice`）。看「幀前」這類不在重建裡的
/// 工作是誰。每 0.25ms 取一次樣，一幀幾毫秒只有十幾個樣本，看大宗不看細節。
final bool frameCpu = Platform.environment['FRAME_CPU'] == '1';

/// 連上這個測試自己的 VM service（[FRAME_GC]、[FRAME_CPU] 共用）。
Future<(VmService, String)> _connectVm(String flag) async {
  final http = (await Service.getInfo()).serverUri;
  if (http == null) {
    throw StateError(
      '$flag=1 要加 --enable-vmservice：flutter test --enable-vmservice …',
    );
  }
  final path = http.path.endsWith('/') ? http.path : '${http.path}/';
  final vm = await vmServiceConnectUri(
    http.replace(scheme: 'ws', path: '${path}ws').toString(),
  );
  return (vm, Service.getIsolateId(Isolate.current)!);
}

/// [frameCpu]：錄完後照每一幀的時間區間取回 CPU 取樣。
class _CpuProfile {
  _CpuProfile._(this._vm, this._isolate);

  final VmService _vm;
  final String _isolate;

  static Future<_CpuProfile> start() async {
    final (vm, isolate) = await _connectVm('FRAME_CPU');
    await vm.setFlag('profile_period', '250');
    await vm.clearCpuSamples(isolate);
    return _CpuProfile._(vm, isolate);
  }

  /// 每個 [windows]（[Timeline.now] 的時鐘的起訖）裡的樣本：自己花最多的前
  /// 6 個函式，與最靠近堆疊頂端的 App 函式前 6 個（各附樣本數）。整段只向
  /// VM 要一次：每要一次 VM 都要把整個 App 的函式表整理一遍，逐幀要的話
  /// 幾十幀就要好幾分鐘。
  Future<List<List<String>>> top(List<(int, int)> windows) async {
    if (windows.isEmpty) return const [];
    final from = windows.map((w) => w.$1).reduce(math.min);
    final to = windows.map((w) => w.$2).reduce(math.max);
    final samples = await _vm
        .getCpuSamples(_isolate, from, to - from)
        .timeout(
          const Duration(minutes: 2),
          onTimeout: () => throw StateError('FRAME_CPU：VM 兩分鐘內沒交回取樣'),
        );
    final functions = samples.functions ?? const <ProfileFunction>[];
    final all = samples.samples ?? const <CpuSample>[];
    return [
      for (final (start, end) in windows)
        _summarize(
          functions,
          all.where((s) {
            final t = s.timestamp ?? -1;
            return t >= start && t < end;
          }),
        ),
    ];
  }

  static List<String> _summarize(
    List<ProfileFunction> functions,
    Iterable<CpuSample> list,
  ) {
    String nameOf(int index) {
      final function = functions[index].function;
      final name = function is FuncRef
          ? [
              if (function.owner case ClassRef(:final name?)) name,
              function.name,
            ].join('.')
          : (function is NativeFunction ? function.name : '$function');
      return name ?? '?';
    }

    bool isApp(int index) =>
        (functions[index].resolvedUrl ?? '').contains('night_reader/');
    final self = <String, int>{};
    final app = <String, int>{};
    var count = 0;
    for (final sample in list) {
      count++;
      final stack = sample.stack ?? const <int>[];
      if (stack.isEmpty) continue;
      final top = nameOf(stack.first);
      self[top] = (self[top] ?? 0) + 1;
      final inApp = stack.where(isApp).firstOrNull;
      if (inApp != null) {
        final name = nameOf(inApp);
        app[name] = (app[name] ?? 0) + 1;
      }
    }
    String rank(Map<String, int> counts) {
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(6).map((e) => '${e.key}×${e.value}').join('、');
    }

    return [
      if (self.isNotEmpty) '樣本 $count，自己花最多：${rank(self)}',
      if (app.isNotEmpty) '落在 App 程式：${rank(app)}',
    ];
  }

  Future<void> dispose() => _vm.dispose();
}

/// 一次讓主執行緒停住的回收：開始時間（[Timeline.now] 的時鐘）、多久、是
/// 新生區還是舊生區。
typedef _GcPause = ({int start, int micros, bool young});

/// 從 VM 的時間軸讀每次回收的起訖。不逐幀向 VM 查詢：查詢的回應在主執行緒
/// 上組出來，每幀查一次產生的物件本身就讓回收變多。同一個 isolate group
/// 共用記憶體，資料庫 isolate 引發的回收也會讓主執行緒停住，所以不分是哪
/// 條執行緒觸發的。
class _GcTimeline {
  _GcTimeline._(
    this._vm,
    this._isolate,
    this._group,
    this._start,
    this._scavengesAtStart,
    this._counted,
  ) : _origin = _start;

  final VmService _vm;
  final String _isolate;

  /// 時間軸也記著別的 isolate group 的回收（例如 VM service 自己的），那些
  /// 不會讓 App 停住。
  final String _group;

  /// 開始記錄的時間；之前的事件不算。
  final int _start;

  /// 開始時 VM 數到的新生區回收次數，在 [_start] 之後、[_counted] 之前讀的：
  /// 這段時間裡的回收可能算進了這個數，也可能沒有。
  final int _scavengesAtStart;
  final int _counted;

  /// 下次取回從哪裡開始。
  int _origin;
  final _open = <String, List<int>>{};
  final _seen = <String>{};
  final _pauses = <_GcPause>[];

  /// 停住主執行緒的整段回收（值是否為新生區）。
  static const _kinds = {
    'CollectNewGeneration': true,
    'EvacuateNewGeneration': true,
    'CollectOldGeneration': false,
    'StartConcurrentMarking': false,
  };

  static Future<_GcTimeline> start() async {
    final (vm, isolate) = await _connectVm('FRAME_GC');
    await vm.setVMTimelineFlags(['GC']);
    final info = (await vm.getIsolate(isolate)).json!;
    final start = Timeline.now;
    final scavenges = await _scavenges(vm, isolate);
    return _GcTimeline._(
      vm,
      isolate,
      info['isolateGroupId'] as String,
      start,
      scavenges,
      Timeline.now,
    );
  }

  static Future<int> _scavenges(VmService vm, String isolate) async {
    final heaps = (await vm.getIsolate(isolate)).json!['_heaps'] as Map;
    return (heaps['new'] as Map)['collections'] as int;
  }

  /// 取回上次之後的事件。時間軸的緩衝區有上限，錄得久要中途取；在幀與幀
  /// 之間呼叫，不算進任何一幀。每次往前多取 0.1 秒：事件寫進時間軸會晚一點，
  /// 只照時間切會漏掉剛好在交界之前發生、取的時候還沒寫進去的那筆。
  Future<void> drain() async {
    final now = Timeline.now;
    final from = math.max(_start, _origin - 100000);
    final timeline = await _vm.getVMTimeline(
      timeOriginMicros: from,
      timeExtentMicros: now - from,
    );
    _origin = now;
    for (final event in timeline.traceEvents ?? const <TimelineEvent>[]) {
      final e = event.json!;
      final young = _kinds[e['name']];
      if (young == null || (e['args'] as Map?)?['isolateGroupId'] != _group) {
        continue;
      }
      final ts = e['ts'] as int;
      if (ts < _start) continue;
      final key = '${e['tid']}/${e['name']}';
      // 重疊的那 0.1 秒裡的事件兩次都會拿到。
      if (!_seen.add('$key/${e['ph']}/$ts')) continue;
      switch (e['ph']) {
        case 'X':
          _pauses.add((start: ts, micros: e['dur'] as int, young: young));
        case 'B':
          (_open[key] ??= []).add(ts);
        case 'E':
          final begins = _open[key];
          if (begins == null || begins.isEmpty) continue;
          final begin = begins.removeLast();
          _pauses.add((start: begin, micros: ts - begin, young: young));
      }
    }
  }

  /// 收尾：拿 VM 自己數的新生區回收次數核對，緩衝區滿了掉事件時直接失敗；
  /// 頭尾讀次數那一小段裡的回收算不算得到說不準，不列入核對。包在舊生區
  /// 回收裡的那次新生區回收不重複算。
  Future<List<_GcPause>> stop() async {
    final reading = Timeline.now;
    final counted = await _scavenges(_vm, _isolate) - _scavengesAtStart;
    await drain();
    await dispose();
    final young = _pauses.where((p) => p.young);
    final unsure = young
        .where((p) => p.start < _counted || p.start >= reading)
        .length;
    final seen = young.length;
    if (counted > seen || counted < seen - unsure) {
      throw StateError(
        '時間軸記到 $seen 次新生區回收（頭尾 $unsure 次說不準），VM 數到 '
        '$counted 次：緩衝區滿了，drain 要更常呼叫',
      );
    }
    _pauses.sort((a, b) => a.start.compareTo(b.start));
    final outer = <_GcPause>[];
    var end = -1;
    for (final pause in _pauses) {
      if (pause.start + pause.micros <= end) continue;
      outer.add(pause);
      end = math.max(end, pause.start + pause.micros);
    }
    return outer;
  }

  Future<void> dispose() async {
    await _vm.setVMTimelineFlags([]);
    await _vm.dispose();
  }
}

/// 一幀一幀推進（每幀 [frameDuration]），直到 [until] 成立後再多 [tailFrames]
/// 幀，記下每一幀的成本。[realAsync] 時每幀之間讓出真實時間，給跑在真的
/// isolate 裡的資料庫回應（`app_harness.dart` 的整個 App 需要）。[note] 在
/// 每一幀畫完時記下畫面在哪一段，摘要裡跟著尖峰幀列出。[onFrame] 在每一幀
/// 開始前呼叫（帶幀序號），拖動這類手勢一幀送一步；它花的時間算在幀前。
/// [afterFrame] 在每一幀量完之後呼叫，不算進任何一幀（逐格錄影存畫面用）。
Future<List<FrameCost>> recordFrames(
  WidgetTester tester, {
  required bool Function() until,
  String? Function()? note,
  Future<void> Function(int frame)? onFrame,
  Future<void> Function(int frame)? afterFrame,
  int tailFrames = 0,
  int maxFrames = 1200,
  Duration frameDuration = const Duration(milliseconds: 16),
  bool realAsync = false,
}) async {
  final previous = (
    FlutterTimeline.debugCollectionEnabled,
    debugProfileBuildsEnabled,
    debugProfileLayoutsEnabled,
    debugProfilePaintsEnabled,
    debugPrintScheduleBuildForStacks,
    debugPrint,
  );
  var dirty = <String, int>{};
  if (framePhases) FlutterTimeline.debugCollectionEnabled = true;
  if (frameAttribution) {
    FlutterTimeline.debugCollectionEnabled = true;
    debugProfileBuildsEnabled = true;
    debugProfileLayoutsEnabled = true;
    debugProfilePaintsEnabled = true;
    // 框架每次排重建都印一段堆疊，只留第一行的 widget 名稱。
    debugPrintScheduleBuildForStacks = true;
    const prefix = 'scheduleBuildFor() called for ';
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null || !message.startsWith(prefix)) return;
      final name = message
          .substring(prefix.length)
          .split(RegExp(r'[(-]'))
          .first;
      dirty[name] = (dirty[name] ?? 0) + 1;
    };
  }
  var costs = <FrameCost>[];
  var gc = frameGc ? await tester.runAsync(_GcTimeline.start) : null;
  final cpu = frameCpu ? await tester.runAsync(_CpuProfile.start) : null;
  // 每一幀從開始到量完的區間（[Timeline.now] 的時鐘），回收照開始時間歸到
  // 這些區間；afterFrame（存畫面）的回收不算進任何一幀。
  final windows = <(int, int)>[];
  final clock = Stopwatch()..start();
  try {
    var tail = -1;
    // 排著的 ticker 會在下一幀走一步（第一步只記下起點，畫面還沒動）。
    var ticking = SchedulerBinding.instance.transientCallbackCount > 0;
    for (var index = 0; index < maxFrames; index++) {
      final moving = ticking;
      final windowStart = Timeline.now;
      var asyncCost = 0;
      if (realAsync) {
        final start = clock.elapsedMicroseconds;
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        asyncCost = clock.elapsedMicroseconds - start;
      }
      var begin = -1;
      var end = -1;
      final timing = SchedulerBinding.instance.scheduleFrameCallback((_) {
        begin = clock.elapsedMicroseconds;
      }, scheduleNewFrame: false);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        end = clock.elapsedMicroseconds;
        ticking = SchedulerBinding.instance.transientCallbackCount > 0;
      });
      if (frameAttribution || framePhases) FlutterTimeline.debugReset();
      final start = clock.elapsedMicroseconds;
      if (onFrame != null) await onFrame(index);
      await tester.pump(frameDuration);
      final stop = clock.elapsedMicroseconds;
      windows.add((windowStart, Timeline.now));
      final top = frameAttribution || framePhases
          ? _exclusive(FlutterTimeline.debugCollect().timedBlocks)
          : const <AggregatedTimedBlock>[];
      // 沒有排到幀（畫面靜止）時整段都算在幀前。量時間的回呼沒跑到，先撤掉
      // 再數 ticker，不然它自己會被當成還有動畫在走。
      if (begin < 0 || end < 0) {
        SchedulerBinding.instance.cancelFrameCallbackWithId(timing);
        begin = end = stop;
        ticking = SchedulerBinding.instance.transientCallbackCount > 0;
      }
      final (from, to) = windows.last;
      costs.add(
        FrameCost(
          index: index,
          beforeFrame: begin - start,
          frame: end - begin,
          afterFrame: stop - end,
          async: asyncCost,
          top: top,
          dirty: dirty,
          note: note?.call(),
          moving: moving,
          dbMicros: dbWork
              .where((w) => w.start >= from && w.start < to)
              .fold(0, (sum, w) => sum + w.micros),
          sliceMicros: sliceWork
              .where((w) => w.start >= from && w.start < to)
              .fold(0, (sum, w) => sum + w.micros),
        ),
      );
      dirty = <String, int>{};
      if (afterFrame != null) await afterFrame(index);
      if (gc != null && index % 30 == 29) await tester.runAsync(gc.drain);
      if (tail < 0 && until()) tail = 0;
      if (tail >= 0 && tail++ >= tailFrames) break;
    }
    if (gc != null) {
      final timeline = gc;
      gc = null; // stop 自己會斷線，失敗時 finally 不再斷一次。
      // runAsync 把例外交給測試框架、回傳 null；沒拿到就照原樣回傳，失敗已經報了。
      final pauses = await tester.runAsync(timeline.stop) ?? const [];
      costs = [
        for (final (i, cost) in costs.indexed)
          cost._withGc(
            pauses.where(
              (p) => p.start >= windows[i].$1 && p.start < windows[i].$2,
            ),
          ),
      ];
    }
    if (cpu != null) {
      final over = [
        for (final (i, cost) in costs.indexed)
          if (cost.moving && cost.judged > frameLimit.inMicroseconds) i,
      ];
      final lines = await tester.runAsync(
        () => cpu.top([for (final i in over) windows[i]]),
      );
      for (final (k, i) in over.indexed) {
        costs[i] = costs[i]._withCpu(lines?[k] ?? const []);
      }
    }
  } finally {
    if (cpu != null) await tester.runAsync(cpu.dispose);
    FlutterTimeline.debugCollectionEnabled = previous.$1;
    debugProfileBuildsEnabled = previous.$2;
    debugProfileLayoutsEnabled = previous.$3;
    debugProfilePaintsEnabled = previous.$4;
    debugPrintScheduleBuildForStacks = previous.$5;
    debugPrint = previous.$6;
    if (gc != null) await tester.runAsync(gc.dispose);
  }
  return costs;
}

/// 每一種區塊自己花的時間（扣掉包在裡面的區塊），由多到少取前 15 個。
/// 直接加總的時間會把外層（Stack、Semantics 這類一路包到底的 widget）算得
/// 最多，看不出是誰在做事。
List<AggregatedTimedBlock> _exclusive(List<TimedBlock> blocks) {
  final sorted = [...blocks]..sort((a, b) => a.start.compareTo(b.start));
  final self = <String, double>{};
  final counts = <String, int>{};
  // 還沒結束的區塊，與它裡面的區塊已經花掉的時間。
  final open = <(TimedBlock, double)>[];
  void close() {
    final (block, inner) = open.removeLast();
    self[block.name] = (self[block.name] ?? 0) + block.duration - inner;
    counts[block.name] = (counts[block.name] ?? 0) + 1;
    if (open.isNotEmpty) {
      final (outer, spent) = open.removeLast();
      open.add((outer, spent + block.duration));
    }
  }

  for (final block in sorted) {
    while (open.isNotEmpty && open.last.$1.end <= block.start) {
      close();
    }
    open.add((block, 0));
  }
  while (open.isNotEmpty) {
    close();
  }
  return [
      for (final MapEntry(:key, :value) in self.entries)
        // 計時的誤差會讓幾乎沒有自己工作的區塊算出一點負值。
        AggregatedTimedBlock(
          name: key,
          duration: math.max(0, value),
          count: counts[key]!,
        ),
    ]
    ..sort((a, b) => b.duration.compareTo(a.duration))
    ..length = math.min(15, self.length);
}

/// 摘要：幀數、中位數、最大值，以及超過 [over] 的每一幀各段成本。動畫中
/// 另外列出扣掉資料庫、排版切片照實算（[FrameCost.judged]）後仍超過的
/// 幀數：那些才是手機上也會超過的（ADR 0036）。
String describeFrames(
  String label,
  List<FrameCost> costs, {
  Duration over = frameLimit,
}) {
  String ms(int us) => (us / 1000).toStringAsFixed(1);
  final limit = ms(over.inMicroseconds);
  final totals = [for (final cost in costs) cost.total]..sort();
  final spikes = costs.where((c) => c.total > over.inMicroseconds);
  // 動畫中與靜止時各自最忙的一幀：重活該落在靜止的時候。
  String peak(bool moving) {
    // 第 0 幀是點下去（或手指按下）後的第一幀，可以重（ADR 0036 第 1 條），
    // 不算進動畫中。
    final frames = costs.where(
      (c) => moving ? c.moving && c.index > 0 : !c.moving,
    );
    if (frames.isEmpty) return ' 0 幀';
    final top = frames.reduce((a, b) => b.total > a.total ? b : a);
    final overLimit = frames.where((c) => c.total > over.inMicroseconds).length;
    final overApp = frames.where((c) => c.judged > over.inMicroseconds).length;
    return ' ${frames.length} 幀，最大 ${ms(top.total)}ms（第 ${top.index} 幀）、'
        '超過 ${limit}ms 的 $overLimit 幀'
        '${moving ? '（扣掉資料庫、排版切片照實算後 $overApp 幀）' : ''}';
  }

  String gc(FrameCost cost) => cost.gcMicros == 0
      ? ''
      : '，其中回收記憶體 ${ms(cost.gcMicros)}ms（新生區 ${cost.scavenges} 次'
            '${cost.oldCollections == 0 ? '' : '、舊生區 ${cost.oldCollections} 次'}）';
  final collected = costs.where((c) => c.gcMicros > 0).toList();

  final lines = [
    '$label：${costs.length} 幀，中位數 ${ms(totals[totals.length ~/ 2])}ms，'
        '最大 ${ms(totals.last)}ms，超過 ${limit}ms 的 ${spikes.length} 幀',
    '  動畫中（不含點下去後的第 0 幀）${peak(true)}；靜止時${peak(false)}',
    if (frameGc)
      '  回收記憶體的 ${collected.length} 幀（動畫中 '
          '${collected.where((c) => c.moving).length} 幀）：'
          '${collected.map((c) => '第 ${c.index} 幀${c.moving ? '［動］' : '［靜］'} ${ms(c.gcMicros)}ms').join('、')}',
    for (final cost in spikes) ...[
      '  第 ${cost.index} 幀${cost.moving ? '［動］' : '［靜］'}'
          '${cost.note == null ? '' : '（${cost.note}）'} '
          '${ms(cost.total)}ms：幀前 ${ms(cost.beforeFrame)}、'
          '幀 ${ms(cost.frame)}、幀後 ${ms(cost.afterFrame)}、'
          '非同步 ${ms(cost.async)}${gc(cost)}'
          '${cost.dbMicros == 0 ? '' : '，其中資料庫 ${ms(cost.dbMicros)}ms'}'
          '${cost.sliceMicros == 0 ? '' : '，其中排版切片 ${ms(cost.sliceMicros)}ms'}'
          '${cost.dbMicros == 0 && cost.sliceMicros == 0 ? '' : '（判斷用 ${ms(cost.judged)}ms）'}',
      if (cost.top.isNotEmpty)
        '    耗時：${cost.top.map((b) => '${b.name} ${(b.duration / 1000).toStringAsFixed(1)}×${b.count}').join('、')}',
      if (cost.dirty.isNotEmpty)
        '    重建起點：${cost.dirty.entries.map((e) => '${e.key}×${e.value}').join('、')}',
      for (final line in cost.cpu) '    CPU：$line',
    ],
  ];
  return lines.join('\n');
}
