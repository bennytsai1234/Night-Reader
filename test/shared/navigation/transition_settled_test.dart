import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// 等過換頁的頁面：進場播完時記下，之後每建一次加一。
class _WaitingPage extends StatefulWidget {
  const _WaitingPage({required this.onBuild});

  final VoidCallback onBuild;

  @override
  State<_WaitingPage> createState() => _WaitingPageState();
}

class _WaitingPageState extends State<_WaitingPage> {
  Future<void>? _entered;
  bool settled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entered ??= TransitionSettled.entered(context).then((_) {
      if (mounted) setState(() => settled = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return Scaffold(
      appBar: const GlassNavHeader(title: '等過換頁'),
      body: Center(child: Text(settled ? '播完' : '進場中')),
    );
  }
}

void main() {
  testWidgets('a page that waited for its entrance is not rebuilt when '
      'another page covers it and goes away', (tester) async {
    var builds = 0;
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) {
            home = context;
            return const Scaffold(body: Text('主頁'));
          },
        ),
      ),
    );
    Navigator.push(
      home,
      MaterialPageRoute<void>(
        builder: (_) => _WaitingPage(onBuild: () => builds++),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('播完'), findsOneWidget);
    final before = builds;

    Navigator.push(
      tester.element(find.text('播完')),
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('上面那頁')),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.pop(tester.element(find.text('上面那頁')));
    await tester.pumpAndSettle();

    // 原本等換頁用 ModalRoute.of，路由狀態一變（被蓋住、露出來）整頁就重建。
    expect(builds, before);
    // 返回鈕照樣在。
    expect(find.byTooltip('返回'), findsOneWidget);
  });
}
