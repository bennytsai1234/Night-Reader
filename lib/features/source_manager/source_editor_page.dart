import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/core/ai_repair/ai_repair_prompt.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import 'source_debug_page.dart';
import 'views/source_edit_basic.dart';
import 'views/source_edit_search.dart';
import 'views/source_edit_explore.dart';
import 'views/source_edit_book_info.dart';
import 'views/source_edit_toc.dart';
import 'views/source_edit_content.dart';

import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';
import 'package:night_reader/shared/widgets/glass/glass_segmented.dart';

/// 編輯器分頁標籤，順序對應 [TabBarView] 的子頁。
const List<String> _tabLabels = ['基礎', '搜尋', '發現', '詳情', '目錄', '正文'];

/// 頁首分段控制佔用的高度（36 軌道加上下內距）。
const double _kTabsHeight = GlassSegmented.trackHeight;

/// 頁首「更多」的動作。
enum _EditorAction { save, login, search, clearCookies, copy, paste }

class SourceEditorPage extends StatefulWidget {
  final BookSource? source;

  /// 存進資料庫一次就呼叫（含登入、搜尋前先存的那一次）。書源管理靠它
  /// 知道回來要重讀清單，就算使用者沒按「儲存」、這一頁不是用 true 關掉的。
  final VoidCallback? onSaved;

  const SourceEditorPage({super.key, this.source, this.onSaved});

  @override
  State<SourceEditorPage> createState() => _SourceEditorPageState();
}

class _SourceEditorPageState extends State<SourceEditorPage>
    with SingleTickerProviderStateMixin {
  late BookSource _editingSource;
  late TabController _tabController;
  final Map<String, TextEditingController> _controllers = {};
  final _bookSourceService = BookSourceService();
  bool _isSaving = false;

  /// 開啟時各欄位的內容；與目前內容不同就是有未儲存的修改。
  late Map<String, String> _initialTexts;
  late int _initialSourceType;
  bool _dirty = false;

  /// 資料庫現在那一筆的網址與內容（非 null 就是已經存過）。登入、搜尋前
  /// 先存檔但留在這一頁，之後再存時照這一份找原來那一筆、比改了哪些規則。
  String? _savedUrl;
  BookSource? _savedSource;

  @override
  void initState() {
    super.initState();
    _editingSource = widget.source == null
        ? BookSource(bookSourceUrl: '')
        : BookSource.fromJson(
            Map<String, dynamic>.from(widget.source!.toJson()),
          );
    _savedUrl = widget.source?.bookSourceUrl;
    _savedSource = widget.source == null
        ? null
        : BookSource.fromJson(
            Map<String, dynamic>.from(widget.source!.toJson()),
          );
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _initControllers();
    _initialTexts = {
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };
    _initialSourceType = _editingSource.bookSourceType;
    for (final controller in _controllers.values) {
      controller.addListener(_updateDirty);
    }
  }

  void _updateDirty() {
    final dirty =
        _editingSource.bookSourceType != _initialSourceType ||
        _controllers.entries.any(
          (entry) => entry.value.text != _initialTexts[entry.key],
        );
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  Future<void> _confirmDiscard() async {
    final discard = await showAppConfirm(
      context: context,
      title: '放棄這次的修改？',
      confirmLabel: '放棄',
      destructive: true,
      irreversible: true,
    );
    if (discard && mounted) Navigator.pop(context);
  }

  void _initControllers() {
    _controllers['name'] = TextEditingController(
      text: _editingSource.bookSourceName,
    );
    _controllers['url'] = TextEditingController(
      text: _editingSource.bookSourceUrl,
    );
    _controllers['group'] = TextEditingController(
      text: _editingSource.bookSourceGroup,
    );
    _controllers['comment'] = TextEditingController(
      text: _editingSource.bookSourceComment,
    );
    _controllers['header'] = TextEditingController(text: _editingSource.header);
    _controllers['loginUrl'] = TextEditingController(
      text: _editingSource.loginUrl,
    );
    _controllers['loginUi'] = TextEditingController(
      text: _editingSource.loginUi,
    );
    _controllers['loginCheckJs'] = TextEditingController(
      text: _editingSource.loginCheckJs,
    );

    _controllers['searchUrl'] = TextEditingController(
      text: _editingSource.searchUrl,
    );
    _controllers['ruleSearchBookList'] = TextEditingController(
      text: _editingSource.ruleSearch?.bookList,
    );
    _controllers['ruleSearchName'] = TextEditingController(
      text: _editingSource.ruleSearch?.name,
    );
    _controllers['ruleSearchAuthor'] = TextEditingController(
      text: _editingSource.ruleSearch?.author,
    );
    _controllers['ruleSearchKind'] = TextEditingController(
      text: _editingSource.ruleSearch?.kind,
    );
    _controllers['ruleSearchWordCount'] = TextEditingController(
      text: _editingSource.ruleSearch?.wordCount,
    );
    _controllers['ruleSearchLastChapter'] = TextEditingController(
      text: _editingSource.ruleSearch?.lastChapter,
    );
    _controllers['ruleSearchCoverUrl'] = TextEditingController(
      text: _editingSource.ruleSearch?.coverUrl,
    );
    _controllers['ruleSearchNoteUrl'] = TextEditingController(
      text: _editingSource.ruleSearch?.bookUrl,
    );

    _controllers['exploreUrl'] = TextEditingController(
      text: _editingSource.exploreUrl,
    );
    _controllers['ruleExploreBookList'] = TextEditingController(
      text: _editingSource.ruleExplore?.bookList,
    );
    _controllers['ruleExploreName'] = TextEditingController(
      text: _editingSource.ruleExplore?.name,
    );
    _controllers['ruleExploreAuthor'] = TextEditingController(
      text: _editingSource.ruleExplore?.author,
    );
    _controllers['ruleExploreKind'] = TextEditingController(
      text: _editingSource.ruleExplore?.kind,
    );
    _controllers['ruleExploreWordCount'] = TextEditingController(
      text: _editingSource.ruleExplore?.wordCount,
    );
    _controllers['ruleExploreLastChapter'] = TextEditingController(
      text: _editingSource.ruleExplore?.lastChapter,
    );
    _controllers['ruleExploreCoverUrl'] = TextEditingController(
      text: _editingSource.ruleExplore?.coverUrl,
    );
    _controllers['ruleExploreBookUrl'] = TextEditingController(
      text: _editingSource.ruleExplore?.bookUrl,
    );

    _controllers['ruleBookInfoInit'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.init,
    );
    _controllers['ruleBookInfoName'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.name,
    );
    _controllers['ruleBookInfoAuthor'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.author,
    );
    _controllers['ruleBookInfoIntro'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.intro,
    );
    _controllers['ruleBookInfoKind'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.kind,
    );
    _controllers['ruleBookInfoLastChapter'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.lastChapter,
    );
    _controllers['ruleBookInfoUpdateTime'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.updateTime,
    );
    _controllers['ruleBookInfoCoverUrl'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.coverUrl,
    );
    _controllers['ruleBookInfoTocUrl'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.tocUrl,
    );
    _controllers['ruleBookInfoWordCount'] = TextEditingController(
      text: _editingSource.ruleBookInfo?.wordCount,
    );

    _controllers['ruleTocChapterList'] = TextEditingController(
      text: _editingSource.ruleToc?.chapterList,
    );
    _controllers['ruleTocChapterName'] = TextEditingController(
      text: _editingSource.ruleToc?.chapterName,
    );
    _controllers['ruleTocChapterUrl'] = TextEditingController(
      text: _editingSource.ruleToc?.chapterUrl,
    );
    _controllers['ruleTocNextPage'] = TextEditingController(
      text: _editingSource.ruleToc?.nextPage,
    );

    _controllers['ruleContentContent'] = TextEditingController(
      text: _editingSource.ruleContent?.content,
    );
    _controllers['ruleContentNextPage'] = TextEditingController(
      text: _editingSource.ruleContent?.nextPage,
    );
    _controllers['ruleContentReplace'] = TextEditingController(
      text: _editingSource.ruleContent?.replace,
    );
  }

  void _syncSource() {
    _editingSource.bookSourceName = _controllers['name']!.text.trim();
    _editingSource.bookSourceUrl = _controllers['url']!.text.trim();
    _editingSource.bookSourceGroup = _controllers['group']!.text;
    _editingSource.bookSourceComment = _controllers['comment']!.text;
    _editingSource.header = _controllers['header']!.text;
    _editingSource.searchUrl = _controllers['searchUrl']!.text;
    _editingSource.exploreUrl = _controllers['exploreUrl']!.text;

    // 只改編輯器有的欄位；編輯器沒顯示的規則（例如 webJs、formatJs）原樣保留。
    String? text(String key) => _controllers[key]!.text._emptyToNull;

    _editingSource
      ..loginUrl = text('loginUrl')
      ..loginUi = text('loginUi')
      ..loginCheckJs = text('loginCheckJs');

    (_editingSource.ruleSearch ??= SearchRule())
      ..bookList = text('ruleSearchBookList')
      ..name = text('ruleSearchName')
      ..author = text('ruleSearchAuthor')
      ..kind = text('ruleSearchKind')
      ..wordCount = text('ruleSearchWordCount')
      ..lastChapter = text('ruleSearchLastChapter')
      ..coverUrl = text('ruleSearchCoverUrl')
      ..bookUrl = text('ruleSearchNoteUrl');

    (_editingSource.ruleExplore ??= ExploreRule())
      ..bookList = text('ruleExploreBookList')
      ..name = text('ruleExploreName')
      ..author = text('ruleExploreAuthor')
      ..kind = text('ruleExploreKind')
      ..wordCount = text('ruleExploreWordCount')
      ..lastChapter = text('ruleExploreLastChapter')
      ..coverUrl = text('ruleExploreCoverUrl')
      ..bookUrl = text('ruleExploreBookUrl');

    (_editingSource.ruleBookInfo ??= BookInfoRule())
      ..init = text('ruleBookInfoInit')
      ..name = text('ruleBookInfoName')
      ..author = text('ruleBookInfoAuthor')
      ..intro = text('ruleBookInfoIntro')
      ..kind = text('ruleBookInfoKind')
      ..lastChapter = text('ruleBookInfoLastChapter')
      ..updateTime = text('ruleBookInfoUpdateTime')
      ..coverUrl = text('ruleBookInfoCoverUrl')
      ..tocUrl = text('ruleBookInfoTocUrl')
      ..wordCount = text('ruleBookInfoWordCount');

    (_editingSource.ruleToc ??= TocRule())
      ..chapterList = text('ruleTocChapterList')
      ..chapterName = text('ruleTocChapterName')
      ..chapterUrl = text('ruleTocChapterUrl')
      ..nextTocUrl = text('ruleTocNextPage');

    (_editingSource.ruleContent ??= ContentRule())
      ..content = text('ruleContentContent')
      ..nextContentUrl = text('ruleContentNextPage')
      ..replaceRegex = text('ruleContentReplace');
  }

  /// 存檔。[close] 是從「儲存」按的：存好關掉這一頁；登入與搜尋要帶著
  /// 存好的書源出去，存好留在這一頁，回來接著改。
  Future<bool> _persist({required bool close}) async {
    if (_isSaving) return false;
    _syncSource();
    if (!_validateRequiredFields()) return false;
    setState(() => _isSaving = true);
    try {
      final previousUrl = _savedUrl;
      final url = _editingSource.bookSourceUrl;
      if (url != previousUrl) {
        final existing = await _bookSourceService.getSourceByUrl(url);
        if (!mounted) return false;
        if (existing != null) {
          final overwrite = await showAppConfirm(
            context: context,
            title: '覆蓋「${existing.bookSourceName}」？',
            message: '它用的是同一個網址，儲存後換成這次的內容。',
            confirmLabel: '覆蓋',
            destructive: true,
            irreversible: true,
          );
          if (!overwrite || !mounted) return false;
        }
      }
      // 規則改了，AI 修不好的判斷就不算數了（ADR 0054）。
      final before = _savedSource;
      if (before != null && changedParts(before, _editingSource).isNotEmpty) {
        _editingSource.removeGroup(aiUnfixableSourceGroupTag);
      }
      // 內容改了就記下修改的時間，匯入另一台時才認得出這是新的一版（同 Legado）。
      if (before == null || _dirty) {
        _editingSource.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
      }
      await _bookSourceService.saveEditedSource(
        _editingSource,
        previousUrl: previousUrl,
        editedFrom: previousUrl,
      );
      if (!mounted) return false;
      _savedUrl = url;
      _savedSource = BookSource.fromJson(
        Map<String, dynamic>.from(_editingSource.toJson()),
      );
      _resetDirtyBaseline();
      widget.onSaved?.call();
      if (close) {
        Navigator.pop(context, true);
      }
      return true;
    } on SourceGoneException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: UiText(error.message)));
      }
      return false;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: UiText('儲存失敗，請稍後再試')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 存好了：這一頁的內容就是資料庫那一份，之後離開不用問要不要放棄。
  void _resetDirtyBaseline() {
    _initialTexts = {
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };
    _initialSourceType = _editingSource.bookSourceType;
    if (_dirty) setState(() => _dirty = false);
  }

  Future<void> _runEditorAction(_EditorAction action) async {
    switch (action) {
      case _EditorAction.save:
        await _persist(close: true);
      case _EditorAction.login:
        // 同 Legado：先存好再登入，登入資料才跟著存好的網址。
        if (!await _persist(close: false) || !mounted) return;
        await openSourceLogin(context, _editingSource);
      case _EditorAction.search:
        if (!await _persist(close: false) || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SearchPage(initialSource: _editingSource),
          ),
        );
      case _EditorAction.clearCookies:
        await _clearCookies();
      case _EditorAction.copy:
        await _copySource();
      case _EditorAction.paste:
        await _pasteSource();
    }
  }

  /// 清掉這個書源的 Cookie，表單內容與登入標頭不動。沒有登入網址的書源
  /// 也能清（Legado 編輯頁的「清除 Cookie」）。
  Future<void> _clearCookies() async {
    _syncSource();
    try {
      await clearSourceCookies(_editingSource);
      _showNotice('已清除 Cookie');
    } catch (error, stackTrace) {
      _showNotice(failureMessage('清除 Cookie', error, stackTrace));
    }
  }

  Future<void> _copySource() async {
    _syncSource();
    try {
      await Clipboard.setData(
        ClipboardData(text: jsonEncode(_editingSource.toJson())),
      );
      _showNotice('已複製書源');
    } catch (error, stackTrace) {
      _showNotice(failureMessage('複製書源', error, stackTrace));
    }
  }

  Future<void> _pasteSource() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        _showNotice('剪貼簿沒有可貼上的書源');
        return;
      }
      final pasted = _parsePastedSource(text);
      if (pasted == null) {
        _showNotice('讀不出書源，請貼上書源的 JSON');
        return;
      }
      _replaceEditingSource(pasted);
      _showNotice('已貼上書源');
    } catch (error, stackTrace) {
      _showNotice(failureMessage('貼上書源', error, stackTrace));
    }
  }

  /// 剪貼簿的文字讀成一個書源：JSON 物件，或是陣列時的第一個。
  BookSource? _parsePastedSource(String text) {
    var normalized = text.trim();
    while (normalized.isNotEmpty && normalized.codeUnitAt(0) == 0xFEFF) {
      normalized = normalized.substring(1).trim();
    }
    try {
      final decoded = jsonDecode(normalized);
      final Object? item = decoded is List
          ? (decoded.isEmpty ? null : decoded.first)
          : decoded;
      if (item is! Map) return null;
      return BookSource.fromJson(Map<String, dynamic>.from(item));
    } catch (_) {
      return null;
    }
  }

  /// 貼上的書源填進表單，還沒存：把每一欄換成貼上的內容，離開時照樣問
  /// 要不要放棄。
  void _replaceEditingSource(BookSource source) {
    for (final controller in _controllers.values) {
      controller.removeListener(_updateDirty);
      controller.dispose();
    }
    _controllers.clear();
    _editingSource = source;
    _initControllers();
    for (final controller in _controllers.values) {
      controller.addListener(_updateDirty);
    }
    setState(() {});
    _updateDirty();
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: UiText(message)));
  }

  bool _validateRequiredFields() {
    String? message;
    if (_editingSource.bookSourceName.isEmpty) {
      message = '請輸入書源名稱';
    } else if (_editingSource.bookSourceUrl.isEmpty) {
      message = '請輸入書源網址';
    }
    if (message == null) return true;
    _tabController.animateTo(0);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: UiText(message)));
    return false;
  }

  void _openDebug() {
    _syncSource();
    if (!_validateRequiredFields()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SourceDebugPage(source: _editingSource, debugKey: '我的世界'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: widget.source == null ? '新建書源' : '編輯書源',
        // 有好幾個動作時頁首右邊是「更多」（docs/design/components.md
        // 「左右各一顆」）：儲存和其他書源動作都收在這裡。除錯書源在
        // 「基礎」分頁最下面。
        actions: [
          GlassMenuButton<_EditorAction>(
            tooltip: '更多',
            onSelected: (action) => unawaited(_runEditorAction(action)),
            entriesBuilder: (_) {
              // 選單打開時才讀登入網址：剛打的還沒存也有登入。
              final loginUrl = _controllers['loginUrl']?.text.trim() ?? '';
              return [
                GlassMenuItem(
                  value: _EditorAction.save,
                  label: _isSaving ? '儲存中…' : '儲存',
                  icon: Icons.save_outlined,
                  enabled: !_isSaving,
                ),
                const GlassMenuDivider(),
                GlassMenuItem(
                  value: _EditorAction.login,
                  label: '登入',
                  icon: Icons.login_rounded,
                  enabled: loginUrl.isNotEmpty && !_isSaving,
                ),
                const GlassMenuItem(
                  value: _EditorAction.search,
                  label: '在此書源中搜尋',
                  icon: Icons.search_rounded,
                ),
                const GlassMenuDivider(),
                const GlassMenuItem(
                  value: _EditorAction.clearCookies,
                  label: '清除 Cookie',
                  icon: Icons.cookie_outlined,
                ),
                const GlassMenuItem(
                  value: _EditorAction.copy,
                  label: '複製書源',
                  icon: Icons.content_copy_rounded,
                ),
                const GlassMenuItem(
                  value: _EditorAction.paste,
                  label: '貼上書源',
                  icon: Icons.content_paste_rounded,
                ),
              ];
            },
          ),
        ],
        bottomHeight: _kTabsHeight,
        bottom: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
          child: AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) => GlassSegmented<int>(
              segments: [
                for (var i = 0; i < _tabLabels.length; i++)
                  GlassSegment(i, _tabLabels[i]),
              ],
              selected: _tabController.index,
              onChanged: _tabController.animateTo,
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SourceEditBasic(
            source: _editingSource,
            controllers: _controllers,
            onTypeChanged: (type) {
              setState(() => _editingSource.bookSourceType = type);
              _updateDirty();
            },
            onDebug: _isSaving ? null : _openDebug,
          ),
          SourceEditSearch(controllers: _controllers),
          SourceEditExplore(controllers: _controllers),
          SourceEditBookInfo(controllers: _controllers),
          SourceEditToc(controllers: _controllers),
          SourceEditContent(controllers: _controllers),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}

extension on String {
  String? get _emptyToNull => isEmpty ? null : this;
}
