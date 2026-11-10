import 'package:flutter/material.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/features/source_login/source_browser_page.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';

/// 書源工作失敗時能解決它的那一步（ADR 0038）：要在網頁上驗證的是「前往
/// 驗證」，要登入才讀得到的是「登入」。漫畫閱讀器與有聲書播放器在失敗處
/// 給這一顆，按了回來再重抓。
class SourceFailureRemedy {
  const SourceFailureRemedy({
    required this.label,
    required this.icon,
    required this.run,
  });

  final String label;
  final IconData icon;

  /// 開登入頁或驗證頁；回來後要不要重抓（登入資料沒變就不用）。
  final Future<bool> Function(BuildContext context) run;

  /// [message] 這次失敗在書源 [source] 上有沒有解法；本地書（沒有書源）
  /// 與其他原因是 null。
  static SourceFailureRemedy? of(String message, BookSource? source) {
    if (source == null) return null;
    if (SourceVerificationException.describes(message)) {
      final request = SourceInteraction.verificationFor(source.bookSourceUrl);
      if (request == null) return null;
      return SourceFailureRemedy(
        label: '前往驗證',
        icon: Icons.open_in_browser_rounded,
        run: (context) async {
          await openSourceVerification(
            context,
            sourceUrl: source.bookSourceUrl,
            sourceName: source.bookSourceName,
            request: request,
          );
          return true;
        },
      );
    }
    if (LoginCheckException.describes(message) && source.hasLogin) {
      return SourceFailureRemedy(
        label: '登入',
        icon: Icons.login_rounded,
        run: (context) => openSourceLogin(context, source),
      );
    }
    return null;
  }
}
