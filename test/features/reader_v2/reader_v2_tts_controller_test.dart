import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_controller.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

class _FakeTtsEngine extends ReaderV2TtsEngine {
  final StreamController<String> _events = StreamController<String>.broadcast();
  final List<String> spoken = <String>[];
  bool _playing = false;
  String _text = '';

  @override
  bool get isPlaying => _playing;

  @override
  double get rate => 1;

  @override
  double get pitch => 1;

  @override
  String? get language => null;

  @override
  String get currentSpokenText => _text;

  @override
  Stream<String> get events => _events.stream;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    _text = text;
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _text = '';
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    spoken.add('（接續）$_text');
    _playing = true;
    notifyListeners();
  }

  /// 引擎念完目前這句。
  void complete() {
    _text = '';
    _playing = false;
    _events.add('onComplete');
  }

  @override
  Future<void> setRate(double value) async {}

  @override
  Future<void> setPitch(double value) async {}

  @override
  Future<void> setLanguage(String value) async {}
}

void main() {
  late ReaderV2Runtime runtime;
  late _FakeTtsEngine engine;
  late ReaderV2TtsController tts;

  Future<void> open(Map<int, String?> contents) async {
    final book = Book(
      bookUrl: 'http://tts.test',
      name: '朗讀測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = _FakeBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: [
        for (final index in contents.keys)
          BookChapter(
            url: 'chapter_$index',
            title: '',
            bookUrl: book.bookUrl,
            index: index,
          ),
      ],
      contentLoader: (index, _) async {
        final content = contents[index];
        if (content == null) {
          throw const ReaderV2ContentUnavailableException('暫時無法取得');
        }
        return content;
      },
      bookDao: bookDao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(400, 600),
        style: const ReaderV2LayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 0.8,
          paddingTop: 12,
          paddingBottom: 12,
          paddingLeft: 12,
          paddingRight: 12,
        ),
      ),
      initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    );
    runtime.registerViewportRestore(Object(), (_) async => true);
    await runtime.openBook();
    engine = _FakeTtsEngine();
    tts = ReaderV2TtsController(runtime: runtime, tts: engine);
  }

  tearDown(() {
    tts.dispose();
    engine.dispose();
    runtime.dispose();
  });

  void moveTo(int chapterIndex) {
    runtime.updateVisibleLocation(
      ReaderV2Location(chapterIndex: chapterIndex, charOffset: 0),
    );
  }

  test('a manual jump while reading continues from the new place', () async {
    await open({0: '第一章開頭。', 1: '第二章開頭。'});
    await tts.startFromVisibleLocation();
    expect(engine.spoken.last, '第一章開頭。');

    moveTo(1);
    await tts.followManualJump();

    expect(engine.spoken.last, '第二章開頭。');
    expect(tts.isPlaying, isTrue);
    expect(tts.currentHighlight?.chapterIndex, 1);
  });

  test(
    'a manual jump while paused makes play start at the new place',
    () async {
      await open({0: '第一章開頭。', 1: '第二章開頭。'});
      await tts.startFromVisibleLocation();
      await tts.toggle();
      expect(tts.isPaused, isTrue);

      moveTo(1);
      await tts.followManualJump();
      expect(tts.isPaused, isFalse);
      expect(tts.isPlaying, isFalse);

      await tts.toggle();
      expect(engine.spoken.last, '第二章開頭。');
    },
  );

  test(
    'starting in an empty chapter reads the next chapter with text',
    () async {
      await open({0: '', 1: '', 2: '第三章開頭。'});
      await tts.startFromVisibleLocation();

      expect(engine.spoken, ['第三章開頭。']);
    },
  );

  test('a chapter that fails to load stops reading and says so', () async {
    await open({0: '第一章。', 1: null, 2: '第三章。'});
    await tts.startFromVisibleLocation();
    engine.complete();
    await pumpEventQueue();

    expect(engine.spoken, ['第一章。']);
    expect(tts.currentHighlight, isNull);
    expect(runtime.takeUserNotice(), '第 2 章無法載入，朗讀已停止');
  });

  test('finishing the last chapter says the book has ended', () async {
    await open({0: '唯一的一句。'});
    await tts.startFromVisibleLocation();
    engine.complete();
    await pumpEventQueue();

    expect(tts.currentHighlight, isNull);
    expect(runtime.takeUserNotice(), '已朗讀到書尾');
  });
}
