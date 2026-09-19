import 'dart:ui' show Size;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_controller.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('content generation change cancels stale TTS coordinates', () async {
    var rawText = '舊內容第一句。舊內容第二句。';
    final book = Book(
      bookUrl: 'local://tts-generation.txt',
      name: 'TTS generation',
      author: 'Author',
      origin: 'local',
      originName: 'Local',
    );
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: <BookChapter>[
        BookChapter(
          url: 'chapter_0',
          title: '第一章',
          bookUrl: book.bookUrl,
          index: 0,
          content: rawText,
        ),
      ],
      bookDao: database.bookDao,
      chapterDao: database.chapterDao,
      sourceDao: database.bookSourceDao,
      contentLoader: (_, _) async => rawText,
    );
    final runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: database.bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(240, 320),
        style: const ReaderV2LayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 0.8,
          paddingTop: 12,
          paddingBottom: 12,
          paddingLeft: 12,
          paddingRight: 12,
          textIndent: 0,
        ),
      ),
      initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    );
    addTearDown(runtime.dispose);
    runtime.registerViewportRestore(Object(), (_) async => true);
    await runtime.openBook();

    final engine = _FakeTtsEngine();
    final controller = ReaderV2TtsController(runtime: runtime, tts: engine);
    addTearDown(controller.dispose);

    await controller.startFromVisibleLocation();
    expect(engine.isPlaying, isTrue);
    expect(controller.currentHighlight, isNotNull);
    final generationBefore = repository.contentGeneration;

    rawText = '新的內容已經改變。第二句也不同。';
    await runtime.reloadContentPreservingLocation();
    await Future<void>.delayed(Duration.zero);

    expect(repository.contentGeneration, generationBefore + 1);
    expect(engine.stopCalls, greaterThanOrEqualTo(1));
    expect(engine.isPlaying, isFalse);
    expect(controller.currentHighlight, isNull);
    expect(controller.speechStartLocation, isNull);
  });
}

final class _FakeTtsEngine extends ReaderV2TtsEngine {
  bool _isPlaying = false;
  double _rate = 0.5;
  double _pitch = 1.0;
  String? _language = 'zh-TW';
  String _currentSpokenText = '';
  int stopCalls = 0;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get rate => _rate;

  @override
  double get pitch => _pitch;

  @override
  String? get language => _language;

  @override
  String get currentSpokenText => _currentSpokenText;

  @override
  int get currentWordStart => _currentSpokenText.isEmpty ? -1 : 0;

  @override
  int get currentWordEnd => _currentSpokenText.isEmpty ? -1 : 1;

  @override
  Stream<String> get events => const Stream<String>.empty();

  @override
  Future<void> speak(String text) async {
    _currentSpokenText = text;
    _isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    _currentSpokenText = '';
    _isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    _isPlaying = _currentSpokenText.isNotEmpty;
    notifyListeners();
  }

  @override
  Future<void> setRate(double value) async {
    _rate = value;
  }

  @override
  Future<void> setPitch(double value) async {
    _pitch = value;
  }

  @override
  Future<void> setLanguage(String value) async {
    _language = value;
  }
}
