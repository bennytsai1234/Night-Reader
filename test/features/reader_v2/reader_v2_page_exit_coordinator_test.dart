// 離開閱讀器時「加入書架？」的三個選擇：加入書架、直接退出、取消（留在
// 閱讀器）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/reader_v2/use_cases/coordinators/reader_v2_page_exit_coordinator.dart';

class _Delegate implements ReaderV2ExitFlowDelegate {
  final List<String> calls = [];

  @override
  final Book book = Book(bookUrl: 'https://example.com/b', name: '夜雨聽書');

  @override
  bool shouldPromptAddToBookshelfOnExit() => true;

  @override
  Future<void> persistExitProgress() async => calls.add('persist');

  @override
  Future<void> addCurrentBookToBookshelf() async => calls.add('add');

  @override
  Future<void> discardUnkeptBookStorage() async => calls.add('discard');
}

void main() {
  Future<_Delegate> leave(
    WidgetTester tester,
    Future<void> Function() answer,
  ) async {
    final delegate = _Delegate();
    final coordinator = ReaderV2PageExitCoordinator();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => coordinator.handleExitIntent(
              context: context,
              provider: delegate,
              popNavigator: () => delegate.calls.add('pop'),
            ),
            child: const Text('返回'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('加入書架？'), findsOneWidget);
    await answer();
    await tester.pumpAndSettle();
    expect(find.text('加入書架？'), findsNothing);
    return delegate;
  }

  testWidgets('加入書架：加進書架再離開', (tester) async {
    final delegate = await leave(tester, () => tester.tap(find.text('加入書架')));
    expect(delegate.calls, ['persist', 'add', 'pop']);
  });

  testWidgets('直接退出：清掉不留的書再離開', (tester) async {
    final delegate = await leave(tester, () => tester.tap(find.text('直接退出')));
    expect(delegate.calls, ['persist', 'discard', 'pop']);
  });

  testWidgets('取消、點框外、返回鍵：留在閱讀器，不加也不清', (tester) async {
    for (final answer in <Future<void> Function()>[
      () => tester.tap(find.text('取消')),
      () => tester.tapAt(const Offset(4, 4)),
      () => tester.binding.handlePopRoute(),
    ]) {
      final delegate = await leave(tester, answer);
      expect(delegate.calls, ['persist']);
    }
  });

  testWidgets('三顆按鈕直排，加入書架在最上、取消在最下', (tester) async {
    await leave(tester, () async {
      final add = tester.getCenter(find.text('加入書架'));
      final leaveNow = tester.getCenter(find.text('直接退出'));
      final cancel = tester.getCenter(find.text('取消'));
      expect(add.dx, leaveNow.dx);
      expect(leaveNow.dx, cancel.dx);
      expect(add.dy, lessThan(leaveNow.dy));
      expect(leaveNow.dy, lessThan(cancel.dy));
      await tester.tap(find.text('取消'));
    });
  });
}
