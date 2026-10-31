import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/source_login_ui.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/core/services/source_login_session.dart';
import 'package:night_reader/core/services/webview_cloudflare_solver.dart';
import 'package:night_reader/core/utils/network_utils.dart';
import 'package:night_reader/features/about/external_url_launcher.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'source_browser_page.dart';
import 'source_login_form.dart';

/// 開 [source] 的登入（ADR 0038），關掉後傳回登入資料有沒有變（表單內容、
/// 登入標頭、Cookie）。有變而且現在有登入資料時，拿掉書源的「需要登入」
/// 標記。呼叫端照結果重抓失敗的東西（閱讀器重抓這一章、詳情重抓目錄）。
///
/// 有表單的開表單頁；沒有表單、登入網址是網址的開網頁登入；登入網址是
/// 程式而沒有表單的，開只有右上角登入的表單頁。
///
/// [beforePush] 在推頁之前呼叫，傳回 false 就不開（例如閱讀器要等選單
/// 滑出畫面，這段時間使用者又改做別的事）。
Future<bool> openSourceLogin(
  BuildContext context,
  BookSource source, {
  Future<bool> Function()? beforePush,
}) async {
  final before = await _loginSnapshot(source);
  final saved = await source.getLoginInfoMap() ?? const <String, String>{};
  if (!context.mounted) return false;
  if (beforePush != null && !await beforePush()) return false;
  if (!context.mounted) return false;
  final navigator = Navigator.of(context);
  final form = source.loginForm;
  final loginUrl = source.loginUrl?.trim() ?? '';
  if (form == null && !_looksLikeScript(loginUrl)) {
    await navigator.push<String>(
      MaterialPageRoute(
        builder: (_) => SourceBrowserPage(
          sourceUrl: source.bookSourceUrl,
          url: NetworkUtils.getAbsoluteURL(source.bookSourceUrl, loginUrl),
          title: '登入 · ${source.bookSourceName}',
          headers: source.getHeaderMapSync(),
        ),
      ),
    );
  } else {
    final closed = Completer<void>();
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => SourceLoginPage(
            source: source,
            form: form ?? const SourceLoginUiRows([]),
            savedInfo: saved,
            closed: closed,
          ),
        ),
      ),
    );
    // 表單頁在卸載時才把沒按登入的修改存好，等它存完再比。
    await closed.future;
  }
  final after = await _loginSnapshot(source);
  final changed = after != before;
  if (changed && after.hasData) await _clearLoginRequiredTag(source);
  return changed;
}

/// 清掉 [source] 的登入資料：表單內容、登入標頭、夜讀與手機瀏覽器裡這個
/// 網站的 Cookie（單獨登出一個書源）。
Future<void> clearSourceLoginData(BookSource source) async {
  await source.clearLoginData();
  final uri = Uri.tryParse(source.bookSourceUrl);
  if (uri != null && uri.hasScheme) await WebViewNative.clearCookies(uri);
}

bool _looksLikeScript(String loginUrl) =>
    loginUrl.startsWith('@js:') ||
    loginUrl.toLowerCase().startsWith('<js>') ||
    loginUrl.contains('function ') ||
    loginUrl.contains('\n');

typedef _LoginSnapshot = ({String info, String header, String cookie});

extension on _LoginSnapshot {
  bool get hasData => info.isNotEmpty || header.isNotEmpty || cookie.isNotEmpty;
}

Future<_LoginSnapshot> _loginSnapshot(BookSource source) async => (
  info: await source.getLoginInfo() ?? '',
  header: await source.getLoginHeader() ?? '',
  cookie: await CookieStore().getCookie(source.bookSourceUrl),
);

Future<void> _clearLoginRequiredTag(BookSource source) async {
  try {
    final dao = getIt<BookSourceDao>();
    final stored = await dao.getByUrl(source.bookSourceUrl);
    if (stored == null ||
        !stored.groupTags.contains(loginRequiredSourceGroupTag)) {
      return;
    }
    stored.removeGroup(loginRequiredSourceGroupTag);
    await dao.upsert(stored);
  } catch (error, stackTrace) {
    AppLog.e('拿掉書源的「需要登入」標記失敗', error: error, stackTrace: stackTrace);
  }
}

/// 書源的登入表單（ADR 0038，`DESIGN.md`「書源登入」）：輸入框與書源的
/// 按鈕照書源寫的順序與寬度排，右上角打勾是登入。
///
/// - 輸入框：離開頁面時把改過的存起來（蓋過已存的同名欄位），下次填回。
/// - 一次只跑一個動作：跑的那顆按鈕是選取的樣子，其他按鈕與打勾不能按；
///   離開頁面就停掉它。
/// - 書源的程式在這段工作階段自己的 isolate 執行（[SourceLoginSession]），
///   要開網頁、填驗證碼、顯示訊息都由這一頁接手（[SourceInteraction]）。
class SourceLoginPage extends StatefulWidget {
  const SourceLoginPage({
    super.key,
    required this.source,
    required this.form,
    this.savedInfo = const {},
    this.closed,
  });

  final BookSource source;
  final SourceLoginUi form;

  /// 已存的表單內容，填進輸入框。
  final Map<String, String> savedInfo;

  /// 頁面卸載、改過的輸入框存好後完成。
  final Completer<void>? closed;

  @override
  State<SourceLoginPage> createState() => _SourceLoginPageState();
}

class _SourceLoginPageState extends State<SourceLoginPage>
    implements SourceInteractionHandler {
  late final Future<SourceLoginSession> _session = SourceLoginSession.open(
    widget.source,
  );

  /// 表單的每一列；程式產生的表單還沒拿到時是 null。
  List<SourceLoginRow>? _rows;

  /// 表單讀不出來的原因。
  String? _broken;

  final Map<String, TextEditingController> _fields = {};
  final Map<String, String> _initial = {};

  SourceLoginRow? _running;
  bool _submitting = false;
  CancelToken? _cancel;

  bool get _busy => _running != null || _submitting;

  @override
  void initState() {
    super.initState();
    SourceInteraction.handler = this;
    switch (widget.form) {
      case SourceLoginUiRows(:final rows):
        _setRows(rows);
      case SourceLoginUiScript(:final script):
        unawaited(_loadScriptForm(script));
      case SourceLoginUiBroken(:final reason):
        AppLog.w('${widget.source.bookSourceName} 的登入表單讀不出來: $reason');
        _broken = '登入表單讀不出來';
    }
  }

  void _setRows(List<SourceLoginRow> rows) {
    for (final row in rows.where((row) => row.isField)) {
      if (_fields.containsKey(row.name)) continue;
      final text = widget.savedInfo[row.name] ?? '';
      _initial[row.name] = text;
      _fields[row.name] = TextEditingController(text: text);
    }
    _rows = rows;
  }

  Future<void> _loadScriptForm(String script) async {
    try {
      final rows = await (await _session).loadScriptForm(script);
      if (mounted) setState(() => _setRows(rows));
    } catch (error, stackTrace) {
      final message = failureMessage('讀取登入表單', error, stackTrace);
      if (mounted) setState(() => _broken = message);
    }
  }

  Map<String, String> _formValues() => {
    for (final entry in _fields.entries) entry.key: entry.value.text,
  };

  bool get _dirty =>
      _fields.entries.any((entry) => entry.value.text != _initial[entry.key]);

  @override
  void dispose() {
    if (identical(SourceInteraction.handler, this)) {
      SourceInteraction.handler = null;
    }
    final save = _dirty
        ? saveLoginForm(widget.source, _formValues())
        : Future<void>.value();
    unawaited(
      save
          .catchError(
            (Object error, StackTrace stackTrace) =>
                AppLog.e('存書源登入表單失敗', error: error, stackTrace: stackTrace),
          )
          .whenComplete(() => widget.closed?.complete()),
    );
    _cancel?.cancel();
    unawaited(_session.then((session) => session.close(), onError: (_) {}));
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ── 動作 ─────────────────────────────────────────────────────────

  Future<void> _press(SourceLoginRow button) async {
    final action = button.action?.trim() ?? '';
    if (_busy || action.isEmpty) return;
    if (action.startsWith('http://') || action.startsWith('https://')) {
      await launchExternalUrlWithFeedback(context, action);
      return;
    }
    final cancel = _cancel = CancelToken();
    setState(() => _running = button);
    try {
      final session = await _session;
      await session.pressButton(action, _formValues(), cancelToken: cancel);
    } catch (error, stackTrace) {
      if (mounted && !cancel.isCancelled) {
        _showNotice(failureMessage(button.name.trim(), error, stackTrace));
      }
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _submit() async {
    if (_busy || _rows == null) return;
    final cancel = _cancel = CancelToken();
    setState(() => _submitting = true);
    try {
      final session = await _session;
      final values = _formValues();
      final loggedIn = await session.submit(values, cancelToken: cancel);
      _initial.addAll(values);
      if (!mounted) return;
      if (loggedIn) _showNotice('已登入「${widget.source.bookSourceName}」');
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (mounted && !cancel.isCancelled) {
        _showNotice(failureMessage('登入', error, stackTrace));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showLoginHeader() async {
    final header = await widget.source.getLoginHeader() ?? '';
    if (!mounted) return;
    final copy = await showAppAlert<bool>(
      context: context,
      title: '登入標頭',
      message: header.isEmpty ? '這個書源沒有存登入標頭' : header,
      actions: [
        if (header.isNotEmpty) const AppAlertAction(label: '複製', value: true),
        AppAlertAction(
          label: header.isEmpty ? '好' : '關閉',
          value: false,
          isDefault: header.isEmpty,
        ),
      ],
    );
    if (copy == true) {
      await Clipboard.setData(ClipboardData(text: header));
      _showNotice('已複製登入標頭');
    }
  }

  Future<void> _clearLoginData() async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '清除登入資料',
      message: '清除「${widget.source.bookSourceName}」填過的內容、登入標頭與網站的 Cookie。',
      confirmLabel: '清除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await clearSourceLoginData(widget.source);
      for (final entry in _fields.entries) {
        entry.value.clear();
        _initial[entry.key] = '';
      }
      _showNotice('已清除登入資料');
    } catch (error, stackTrace) {
      _showNotice(failureMessage('清除登入資料', error, stackTrace));
    }
  }

  void _showNotice(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── 書源要使用者做的事（SourceInteractionHandler） ─────────────────

  @override
  Future<String?> browse(SourceBrowseRequest request) async {
    if (!mounted) return null;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SourceBrowserPage(
          sourceUrl: widget.source.bookSourceUrl,
          url: request.url,
          title: request.title.isEmpty
              ? widget.source.bookSourceName
              : request.title,
          headers: request.headers,
        ),
      ),
    );
  }

  @override
  Future<String?> verificationCode(SourceCodeRequest request) async {
    if (!mounted) return null;
    return showStatefulAppAlert<String>(
      context: context,
      fieldTexts: const [''],
      barrierDismissible: false,
      builder: (dialogContext, _, fields) {
        void submit() => Navigator.of(dialogContext).pop(fields.single.text);
        return AppAlert<bool>(
          title: '輸入驗證碼',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: AppRadius.cardSm,
                child: Image.network(
                  request.imageUrl,
                  headers: request.headers,
                  height: 64,
                  fit: BoxFit.contain,
                  errorBuilder: (context, _, _) => const SizedBox(
                    height: 64,
                    child: Center(child: Text('驗證碼圖片載不到')),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AlertTextField(controller: fields.single, autofocus: true),
            ],
          ),
          actions: const [
            AppAlertAction(label: '取消', value: false),
            AppAlertAction(label: '確定', value: true, isDefault: true),
          ],
          onAction: (confirmed) =>
              confirmed ? submit() : Navigator.of(dialogContext).pop(),
        );
      },
    );
  }

  /// 短的訊息從底部跳出；長的或多行的（多半是書源的說明）用提示框，免得
  /// 一閃就消失、看不完。
  @override
  void message(SourceMessage message) {
    if (!mounted) return;
    final text = message.text.trim();
    if (message.long || text.contains('\n') || text.length > 40) {
      unawaited(
        showAppAlert<void>(
          context: context,
          message: text,
          actions: const [
            AppAlertAction(label: '好', value: null, isDefault: true),
          ],
        ),
      );
    } else {
      _showNotice(text);
    }
  }

  // ── 畫面 ─────────────────────────────────────────────────────────

  List<Widget> _items(List<SourceLoginRow> rows) {
    final items = <Widget>[];
    var index = 0;
    while (index < rows.length) {
      final start = index;
      final field = rows[index].isField;
      while (index < rows.length && rows[index].isField == field) {
        index++;
      }
      final run = rows.sublist(start, index);
      final gap = items.isEmpty ? AppSpacing.xs : AppSpacing.xl;
      items.add(
        field
            ? GroupedSection(
                topGap: gap,
                separatorIndent: AppGrouped.rowPadding,
                children: [
                  for (final row in run)
                    SourceLoginField(
                      row: row,
                      controller: _fields[row.name]!,
                      enabled: !_submitting,
                    ),
                ],
              )
            : Padding(
                padding: EdgeInsets.only(top: gap),
                child: SourceLoginButtons(
                  buttons: run,
                  running: _running,
                  enabled: !_submitting,
                  onPressed: _press,
                ),
              ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final rows = _rows;
    final broken = _broken;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: chrome.groupedBackground,
      appBar: GlassNavHeader(
        title: '登入 · ${widget.source.bookSourceName}',
        actions: [
          GlassMenuButton<String>(
            entriesBuilder: (_) => const [
              GlassMenuItem(
                value: 'header',
                label: '登入標頭',
                icon: Icons.badge_outlined,
              ),
              GlassMenuItem(
                value: 'clear',
                label: '清除登入資料',
                icon: Icons.logout_rounded,
                destructive: true,
              ),
            ],
            onSelected: (value) => switch (value) {
              'header' => _showLoginHeader(),
              _ => _clearLoginData(),
            },
          ),
          GlassIconButton(
            icon: Icons.check_rounded,
            tooltip: '登入',
            onPressed: _busy || rows == null || broken != null ? null : _submit,
          ),
        ],
      ),
      body: broken != null
          ? AppStateView(
              icon: Icons.error_outline_rounded,
              title: broken,
              tone: AppStateTone.error,
            )
          : SkeletonSwitcher(
              loading: rows == null,
              backdrop: chrome.groupedBackground,
              skeleton: const _FormSkeleton(),
              builder: (_) => GroupedListView(children: _items(rows ?? [])),
            ),
    );
  }
}

/// 程式產生的表單還沒拿到時的骨架：一般表單的樣子（兩個輸入框、兩排按鈕）。
class _FormSkeleton extends StatefulWidget {
  const _FormSkeleton();

  @override
  State<_FormSkeleton> createState() => _FormSkeletonState();
}

class _FormSkeletonState extends State<_FormSkeleton> {
  static const _field = SourceLoginRow(
    name: '帳號帳號',
    type: SourceLoginRowType.text,
  );
  static const _button = SourceLoginRow(
    name: '按鈕',
    type: SourceLoginRowType.button,
    style: SourceLoginRowStyle(grow: 1, basisPercent: 0.4),
  );

  final TextEditingController _empty = TextEditingController();

  @override
  void dispose() {
    _empty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final items = <Widget>[
      GroupedSection(
        topGap: AppSpacing.xs,
        children: [
          SourceLoginField(row: _field, controller: _empty),
          SourceLoginField(row: _field, controller: _empty),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl),
        child: SourceLoginButtons(
          buttons: const [_button, _button, _button, _button],
          onPressed: (_) {},
        ),
      ),
    ];
    final top = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(
      builder: (context, constraints) => GroupedListSkeleton(
        shapes: [
          for (final item in items)
            GroupedItemShape.of(
              item,
              context: context,
              width: constraints.maxWidth,
            ),
        ],
        top: top,
        cardFill: chrome.groupedSurface,
      ),
    );
  }
}
