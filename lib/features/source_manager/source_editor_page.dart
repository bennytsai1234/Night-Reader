import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book_source.dart';

import 'source_debug_page.dart';
import 'views/source_edit_basic.dart';
import 'views/source_edit_search.dart';
import 'views/source_edit_explore.dart';
import 'views/source_edit_book_info.dart';
import 'views/source_edit_toc.dart';
import 'views/source_edit_content.dart';

import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';

/// 編輯器分頁標籤，順序對應 [TabBarView] 的子頁。
const List<String> _tabLabels = ['基礎', '搜尋', '發現', '詳情', '目錄', '正文'];

/// 頁首分段控制佔用的高度（36 軌道加上下內距）。
const double _kTabsHeight = 36 + AppSpacing.xs * 2;

class SourceEditorPage extends StatefulWidget {
  final BookSource? source;

  const SourceEditorPage({super.key, this.source});

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
  late final Map<String, String> _initialTexts;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _editingSource = widget.source == null
        ? BookSource(bookSourceUrl: '')
        : BookSource.fromJson(
            Map<String, dynamic>.from(widget.source!.toJson()),
          );
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _initControllers();
    _initialTexts = {
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };
    for (final controller in _controllers.values) {
      controller.addListener(_updateDirty);
    }
  }

  void _updateDirty() {
    final dirty = _controllers.entries.any(
      (entry) => entry.value.text != _initialTexts[entry.key],
    );
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  Future<void> _confirmDiscard() async {
    final discard = await showAppConfirm(
      context: context,
      title: '放棄未儲存的修改？',
      message: '離開後，這次的修改都不會保留。',
      confirmLabel: '放棄',
      destructive: true,
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
    _controllers['loginUrl'] = TextEditingController(
      text: _editingSource.loginUrl,
    );
    _controllers['header'] = TextEditingController(text: _editingSource.header);

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
    _editingSource.loginUrl = _controllers['loginUrl']!.text;
    _editingSource.header = _controllers['header']!.text;
    _editingSource.searchUrl = _controllers['searchUrl']!.text;
    _editingSource.exploreUrl = _controllers['exploreUrl']!.text;

    // 只改編輯器有的欄位；編輯器沒顯示的規則（例如 webJs、formatJs）原樣保留。
    String? text(String key) => _controllers[key]!.text._emptyToNull;

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

  Future<void> _save() async {
    if (_isSaving) return;
    _syncSource();
    if (!_validateRequiredFields()) return;
    setState(() => _isSaving = true);
    try {
      final previousUrl = widget.source?.bookSourceUrl;
      final url = _editingSource.bookSourceUrl;
      if (url != previousUrl) {
        final existing = await _bookSourceService.getSourceByUrl(url);
        if (!mounted) return;
        if (existing != null) {
          final overwrite = await showAppConfirm(
            context: context,
            title: '覆蓋現有書源？',
            message: '「${existing.bookSourceName}」已經使用這個網址，儲存後會以這次的內容取代它。',
            confirmLabel: '覆蓋',
            destructive: true,
          );
          if (!overwrite || !mounted) return;
        }
      }
      await _bookSourceService.saveEditedSource(
        _editingSource,
        previousUrl: previousUrl,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('儲存失敗，請稍後再試')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
        .showSnackBar(SnackBar(content: Text(message)));
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
        actions: [
          GlassIconButton(
            tooltip: '除錯書源',
            icon: Icons.bug_report_outlined,
            onPressed: _isSaving ? null : _openDebug,
          ),
          Semantics(
            label: '儲存書源',
            child: GlassTextButton(
              label: _isSaving ? '儲存中…' : '儲存',
              emphasized: true,
              onPressed: _isSaving ? null : _save,
            ),
          ),
        ],
        bottomHeight: _kTabsHeight,
        bottom: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppGrouped.margin,
            AppSpacing.xs,
            AppGrouped.margin,
            AppSpacing.xs,
          ),
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
          SourceEditBasic(source: _editingSource, controllers: _controllers),
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
