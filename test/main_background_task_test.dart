import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/main.dart';

void main() {
  group('runBackgroundTask', () {
    test('initializes DI before loading and logging on success', () async {
      final events = <String>[];

      final result = await runBackgroundTask<int>(
        initialize: () async {
          events.add('initialize');
        },
        loadBookshelf: () async {
          events.add('load');
          return [1, 2, 3];
        },
        logInfo: (message) {
          events.add('log: $message');
        },
      );

      expect(result, isTrue);
      expect(events, [
        'initialize',
        'load',
        'log: Background Task: Checking updates for 3 books',
      ]);
    });

    test('returns false and stops when initialization fails', () async {
      final events = <String>[];

      final result = await runBackgroundTask<int>(
        initialize: () async {
          events.add('initialize');
          throw StateError('initialization failed');
        },
        loadBookshelf: () async {
          events.add('load');
          return const [];
        },
        logInfo: (message) {
          events.add('log');
        },
      );

      expect(result, isFalse);
      expect(events, ['initialize']);
    });

    test(
      'returns false and skips logging when bookshelf loading fails',
      () async {
        final events = <String>[];

        final result = await runBackgroundTask<int>(
          initialize: () async {
            events.add('initialize');
          },
          loadBookshelf: () async {
            events.add('load');
            throw StateError('load failed');
          },
          logInfo: (message) {
            events.add('log');
          },
        );

        expect(result, isFalse);
        expect(events, ['initialize', 'load']);
      },
    );
  });
}
