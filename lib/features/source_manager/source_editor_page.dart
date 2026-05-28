import 'package:flutter/material.dart';
import 'package:reader/core/models/book_source.dart';
import 'source_debug_page.dart';
import 'views/source_edit_basic.dart';
import 'views/source_edit_search.dart';
import 'views/source_edit_explore.dart';
import 'views/source_edit_book_info.dart';
import 'views/source_edit_toc.dart';
import 'views/source_edit_content.dart';
import 'package:reader/core/services/book_source_service.dart';

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

  @override
  void initState() {
    super.initState();
    _editingSource = widget.source ?? BookSource(bookSourceUrl: '');
    _tabController = TabController(length: 6, vsync: this);
    _initControllers();
  }

  void _initControllers() {
    // 基礎資訊
    _controllers['name'] = TextEditingController(
      text: _editingSource.bookSourceName,
    );
    _controllers['url'] = TextEditingController(
      text: _editingSource.bookSourceUrl,
    );
    _controllers['icon'] = TextEditingController(
      text: _editingSource.bookSourceIcon,
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

    // 搜尋規則
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

    // 發現規則
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

    // 詳情規則
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

    // 目錄規則
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

    // 正文規則
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
    _editingSource.bookSourceName = _controllers['name']!.text;
    _editingSource.bookSourceUrl = _controllers['url']!.text;
    _editingSource.bookSourceIcon = _controllers['icon']!.text;
    _editingSource.bookSourceGroup = _controllers['group']!.text;
    _editingSource.bookSourceComment = _controllers['comment']!.text;
    _editingSource.loginUrl = _controllers['loginUrl']!.text;
    _editingSource.header = _controllers['header']!.text;
    _editingSource.searchUrl = _controllers['searchUrl']!.text;
    _editingSource.exploreUrl = _controllers['exploreUrl']!.text;

    _editingSource.ruleSearch = SearchRule(
      bookList: _controllers['ruleSearchBookList']!.text._emptyToNull,
      name: _controllers['ruleSearchName']!.text._emptyToNull,
      author: _controllers['ruleSearchAuthor']!.text._emptyToNull,
      kind: _controllers['ruleSearchKind']!.text._emptyToNull,
      wordCount: _controllers['ruleSearchWordCount']!.text._emptyToNull,
      lastChapter: _controllers['ruleSearchLastChapter']!.text._emptyToNull,
      coverUrl: _controllers['ruleSearchCoverUrl']!.text._emptyToNull,
      bookUrl: _controllers['ruleSearchNoteUrl']!.text._emptyToNull,
    );

    _editingSource.ruleExplore = ExploreRule(
      bookList: _controllers['ruleExploreBookList']!.text._emptyToNull,
      name: _controllers['ruleExploreName']!.text._emptyToNull,
      author: _controllers['ruleExploreAuthor']!.text._emptyToNull,
      kind: _controllers['ruleExploreKind']!.text._emptyToNull,
      wordCount: _controllers['ruleExploreWordCount']!.text._emptyToNull,
      lastChapter: _controllers['ruleExploreLastChapter']!.text._emptyToNull,
      coverUrl: _controllers['ruleExploreCoverUrl']!.text._emptyToNull,
      bookUrl: _controllers['ruleExploreBookUrl']!.text._emptyToNull,
    );

    _editingSource.ruleBookInfo = BookInfoRule(
      init: _controllers['ruleBookInfoInit']!.text._emptyToNull,
      name: _controllers['ruleBookInfoName']!.text._emptyToNull,
      author: _controllers['ruleBookInfoAuthor']!.text._emptyToNull,
      intro: _controllers['ruleBookInfoIntro']!.text._emptyToNull,
      kind: _controllers['ruleBookInfoKind']!.text._emptyToNull,
      lastChapter: _controllers['ruleBookInfoLastChapter']!.text._emptyToNull,
      updateTime: _controllers['ruleBookInfoUpdateTime']!.text._emptyToNull,
      coverUrl: _controllers['ruleBookInfoCoverUrl']!.text._emptyToNull,
      tocUrl: _controllers['ruleBookInfoTocUrl']!.text._emptyToNull,
      wordCount: _controllers['ruleBookInfoWordCount']!.text._emptyToNull,
    );

    _editingSource.ruleToc = TocRule(
      chapterList: _controllers['ruleTocChapterList']!.text._emptyToNull,
      chapterName: _controllers['ruleTocChapterName']!.text._emptyToNull,
      chapterUrl: _controllers['ruleTocChapterUrl']!.text._emptyToNull,
      nextTocUrl: _controllers['ruleTocNextPage']!.text._emptyToNull,
    );

    _editingSource.ruleContent = ContentRule(
      content: _controllers['ruleContentContent']!.text._emptyToNull,
      nextContentUrl: _controllers['ruleContentNextPage']!.text._emptyToNull,
      replaceRegex: _controllers['ruleContentReplace']!.text._emptyToNull,
    );
  }

  Future<void> _save() async {
    _syncSource();
    await BookSourceService().saveSource(_editingSource);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source == null ? '新建書源' : '編輯書源'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              _syncSource();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => SourceDebugPage(
                        source: _editingSource,
                        debugKey: '我的世界',
                      ),
                ),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '基礎'),
            Tab(text: '搜尋'),
            Tab(text: '發現'),
            Tab(text: '詳情'),
            Tab(text: '目錄'),
            Tab(text: '正文'),
          ],
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
