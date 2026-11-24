import 'package:flutter/material.dart';
import 'package:night_reader/core/app_lock/app_lock.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';

/// 鎖的畫面（ADR 0083）：蓋在所有頁面、對話框與選單上面。鎖住時底下不收
/// 點擊、不出鍵盤、讀屏讀不到、動畫停住；解鎖後鎖的畫面淡出，播完才讓開
/// App 的進場開始（[AppLock.markOpened]）。
///
/// 掛在 `MaterialApp.builder` 裡、介面語言之下。
class AppLockScope extends StatefulWidget {
  const AppLockScope({super.key, required this.child, this.lock});

  final Widget child;

  /// 測試用；正式畫面用 [AppLock.instance]。
  final AppLock? lock;

  @override
  State<AppLockScope> createState() => _AppLockScopeState();
}

class _AppLockScopeState extends State<AppLockScope>
    with SingleTickerProviderStateMixin {
  late final AppLock _lock = widget.lock ?? AppLock.instance;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    value: _lock.lockState.value.covering ? 1 : 0,
  );
  late AppLockState _shown = _lock.lockState.value;

  @override
  void initState() {
    super.initState();
    _lock.lockState.addListener(_onState);
    _fade.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _lock.markOpened();
    });
  }

  @override
  void dispose() {
    _lock.lockState.removeListener(_onState);
    _fade.dispose();
    super.dispose();
  }

  void _onState() {
    final next = _lock.lockState.value;
    final previous = _shown;
    setState(() => _shown = next);
    if (next.covering) {
      _fade.value = 1;
      return;
    }
    // 解鎖：淡出。離開不到 5 分鐘回來：鎖的畫面沒有被看到過，直接拿掉。
    if (previous.phase == AppLockPhase.away) {
      _fade.value = 0;
    } else {
      _fade.reverse(from: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final covering = _shown.covering;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        TickerMode(
          enabled: !covering,
          child: ExcludeFocus(
            excluding: covering,
            child: ExcludeSemantics(
              excluding: covering,
              child: IgnorePointer(ignoring: covering, child: widget.child),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _fade,
          builder: (context, child) {
            if (_fade.value == 0) return const SizedBox.shrink();
            return Positioned.fill(
              child: Opacity(opacity: _fade.value, child: child),
            );
          },
          child: _LockScreen(
            showUnlock:
                _shown.promptFailed && _shown.phase == AppLockPhase.locked,
            onUnlock: _lock.unlock,
          ),
        ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.showUnlock, required this.onUnlock});

  final bool showUnlock;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 擋住底下所有點擊；鎖的畫面自己只有「解鎖」一顆。
    return AbsorbPointer(
      absorbing: !showUnlock,
      // 蓋在導覽之上、外面沒有頁面的 Material：自己墊一層，字才有 App 的
      // 字樣（不然是 Flutter 標錯用的黃色底線）。
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.lg),
              // 位置一直留著，按了取消後「解鎖」出現，鎖的圖示不跳。
              AnimatedOpacity(
                opacity: showUnlock ? 1 : 0,
                duration: AppMotion.fade,
                curve: AppMotion.fadeCurve,
                child: PlainTextAction(
                  label: '解鎖',
                  onPressed: showUnlock ? onUnlock : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
