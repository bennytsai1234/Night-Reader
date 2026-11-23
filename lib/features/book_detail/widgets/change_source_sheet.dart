import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/source/source_interaction.dart';
import 'package:night_reader/core/source_switch/same_book.dart';
import 'package:night_reader/core/source_switch/source_switch_service.dart';
import 'package:night_reader/features/book_detail/widgets/borrow_chapter_toc.dart';
import 'package:night_reader/features/source_login/source_browser_page.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';
import 'package:night_reader/features/book_detail/source/book_detail_change_source_provider.dart';
import 'package:night_reader/features/book_detail/widgets/book_detail_change_source_filter_bar.dart';
import 'package:night_reader/features/book_detail/widgets/book_detail_change_source_item.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/popups/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 換源面板選源後的處理結果（成功/失敗 + 提示訊息）。
typedef ChangeSourceOutcome = ({bool success, String message});

/// 換源面板選源回呼。
///
/// 詳情頁情境不傳，沿用 [BookDetailProvider.changeSource]；閱讀器情境傳入走
/// [SourceSwitchService] 的回呼。回呼負責執行換源並回傳結果，由面板顯示
/// SnackBar、成功時 pop。[toc] 是清單已經抓好的它的詳情與目錄，交給
/// [SourceSwitchService.prepareSwitch] 就不用再抓一次。
typedef OnSelectSource = Future<ChangeSourceOutcome> Function(
  SearchBook selected,
  SourceToc? toc,
);

/// 換到 [selected]：準備好、寫進資料庫，回傳換好的結果。網站搜不到、抓不到
/// 時丟 [isSourceSwitchUnavailable] 認得的錯，面板寫出原因、留著讓人選別的。
typedef SwitchToSource = Future<PreparedSourceSwitch> Function(
  SearchBook selected,
  SourceToc? toc,
);

/// 單章借源（ADR 0080）：用 [source] 書源抓好的 [toc] 的第 [index] 章蓋進
/// 主書源那一章；[cancelToken] 是關掉面板、改選別章時取消還沒寫進去的
/// 那次。網站搜不到、抓不到時丟 [isSourceSwitchUnavailable] 認得的錯，面板
/// 寫出原因、留著讓人選別的。
typedef BorrowFromSource = Future<void> Function(
  BookSource source,
  SourceToc toc,
  int index,
  CancelToken cancelToken,
);

/// 單章借源要借的主書源那一章 [chapter]，與借的做法 [borrowFrom]。
class ChapterBorrow {
  const ChapterBorrow({required this.chapter, required this.borrowFrom});

  final BookChapter chapter;
  final BorrowFromSource borrowFrom;
}

/// 選了書源、打開了它的目錄：[estimated] 是估計同一章在 [toc] 的第幾個。
typedef _Lender = ({
  SearchBook candidate,
  BookSource source,
  SourceToc toc,
  int estimated,
});

enum _SourceFilter { checkAuthor, excludeFarWordCount }

class ChangeSourceSheet extends StatelessWidget {
  final Book book;

  /// 詳情頁情境：提供 detailProvider，走既有 changeSource 行為。
  final BookDetailProvider? detailProvider;

  /// 閱讀器情境：提供自訂選源回呼（走 SourceSwitchService）。
  final OnSelectSource? onSelectSource;

  /// 單章借源（[showForBorrow]）：點書源打開它的目錄，點一章才借。
  final ChapterBorrow? borrow;

  const ChangeSourceSheet({
    super.key,
    required this.book,
    this.detailProvider,
    this.onSelectSource,
    this.borrow,
  }) : assert(
         detailProvider != null || onSelectSource != null || borrow != null,
         'ChangeSourceSheet 需要 detailProvider、onSelectSource 或 borrow 其中之一',
       );

  /// 閱讀器的單章借源（ADR 0080）：和換源同一套搜尋與清單；點書源打開它
  /// 的目錄、捲到估計的那一章，點一章由 [borrowFrom] 借進主書源的
  /// [chapter]。借成了面板收起，回傳借的書源；關掉面板是 null，還沒寫進
  /// 去的那次跟著取消（已經寫進去的照樣回傳）。
  static Future<BookSource?> showForBorrow({
    required BuildContext context,
    required Book book,
    required BookChapter chapter,
    required BorrowFromSource borrowFrom,
    BoxConstraints? constraints,
  }) async {
    Future<BookSource?>? latest;
    await AppBottomSheet.showCustom<void>(
      context: context,
      constraints: constraints,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeSourceSheet(
        book: book,
        borrow: ChapterBorrow(
          chapter: chapter,
          borrowFrom: (source, toc, index, cancelToken) {
            final borrowing = borrowFrom(source, toc, index, cancelToken);
            latest = borrowing.then<BookSource?>(
              (_) => source,
              onError: (_) => null,
            );
            return borrowing;
          },
        ),
      ),
    );
    return latest;
  }

  /// 閱讀器、漫畫閱讀器與有聲書播放器的換源：打開清單，選了一個就由
  /// [switchTo] 換源，回傳換好的結果，沒換成是 null。換源途中關掉清單
  /// （返回、點遮罩、下拉）不會取消這次換源：等它做完才回傳，呼叫端照樣
  /// 換到新書源，畫面不會停在已經換掉的舊書源（同 Legado，換源視窗關了
  /// 換源照樣做完）。
  static Future<PreparedSourceSwitch?> showForSwitch({
    required BuildContext context,
    required Book book,
    required SwitchToSource switchTo,
    BoxConstraints? constraints,
  }) async {
    Future<PreparedSourceSwitch?>? latest;
    await AppBottomSheet.showCustom<void>(
      context: context,
      constraints: constraints,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeSourceSheet(
        book: book,
        onSelectSource: (selected, toc) {
          final switching = switchTo(selected, toc);
          // 失敗由面板寫出原因（認不得的錯往上報），這裡只等它結束。
          latest = switching.then<PreparedSourceSwitch?>(
            (prepared) => prepared,
            onError: (_) => null,
          );
          return switching.then(
            (prepared) => (
              success: true,
              message: '已切換到 ${prepared.source.bookSourceName}',
            ),
            onError: (Object error, StackTrace stackTrace) {
              if (!isSourceSwitchUnavailable(error)) {
                Error.throwWithStackTrace(error, stackTrace);
              }
              return (success: false, message: failureMessage('換源', error));
            },
          );
        },
      ),
    );
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BookDetailChangeSourceProvider(book),
      child: _ChangeSourceContent(
        originalBook: book,
        detailProvider: detailProvider,
        onSelectSource: onSelectSource,
        borrow: borrow,
      ),
    );
  }
}

class _ChangeSourceContent extends StatefulWidget {
  final Book originalBook;
  final BookDetailProvider? detailProvider;
  final OnSelectSource? onSelectSource;
  final ChapterBorrow? borrow;

  const _ChangeSourceContent({
    required this.originalBook,
    required this.detailProvider,
    required this.onSelectSource,
    required this.borrow,
  });

  @override
  State<_ChangeSourceContent> createState() => _ChangeSourceContentState();
}

class _ChangeSourceContentState extends State<_ChangeSourceContent> {
  final TextEditingController _filterController = TextEditingController();
  bool _isSwitchingSource = false;

  /// 單章借源打開了目錄的那個書源；null 時列書源。
  _Lender? _lender;

  /// 正在借的那一次：關掉面板、回到書源清單、改點別章時取消。
  CancelToken? _borrowing;

  @override
  void dispose() {
    _borrowing?.cancel();
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BookDetailChangeSourceProvider>();
    final sources = provider.filteredResults
        .where((result) => result.name == widget.originalBook.name)
        .toList();

    final chrome = AppChrome.of(context);
    final count = sources.length;
    final lender = _lender;
    if (lender != null) return _buildLender(lender);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: chrome.groupedBackground,
        borderRadius: AppRadius.topSheetLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(provider),
          BookDetailChangeSourceFilterBar(
            provider: provider,
            filterController: _filterController,
          ),
          SizedBox(
            height: 2,
            child: provider.isSearching || _isSwitchingSource
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          // 目前的書源固定在清單上方：一打開就看得到現在讀的是哪一個，
          // 不用在清單裡找；它不參加搜尋，所以不會出現在下面的清單裡。
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: GroupedSliceItem(
              index: 0,
              count: 1,
              child: BookDetailChangeSourceItem(
                searchBook: widget.originalBook.toSearchBook(),
                chapterCount: widget.originalBook.totalChapterNum > 0
                    ? widget.originalBook.totalChapterNum
                    : null,
                isCurrent: true,
              ),
            ),
          ),
          // 搜尋狀態與來源數是資料，用粗字（ADR 0076）；夾在目前來源卡與
          // 清單中間，上下一樣。
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppGrouped.margin + AppGrouped.rowPadding,
              AppGrouped.sectionGap,
              AppGrouped.margin + AppGrouped.rowPadding,
              AppGrouped.sectionGap,
            ),
            child: DefaultTextStyle.merge(
              style: AppTextStyles.bodyBase.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: UiText(
                      _isSwitchingSource
                          ? (widget.borrow == null ? '正在切換來源…' : '正在載入目錄…')
                          : provider.status,
                    ),
                  ),
                  if (count > 0) UiText('共 $count 個來源'),
                ],
              ),
            ),
          ),
          Expanded(
            child: IgnorePointer(
              ignoring: _isSwitchingSource,
              // 一個來源都沒找到時，上面那一行狀態已經寫了原因（沒找到、或
              // 書源都失敗），這裡不再寫一次；找到了但被篩選擋掉才提示。
              child: sources.isEmpty && !provider.isSearching
                  ? Center(
                      child: provider.allResults.isEmpty
                          ? null
                          : UiText(
                              '沒有符合篩選的來源',
                              style: AppTextStyles.bodyBase.copyWith(
                                color: chrome.sectionText,
                              ),
                            ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom:
                            MediaQuery.paddingOf(context).bottom +
                            AppGrouped.sectionGap,
                      ),
                      itemCount: count,
                      itemBuilder: (ctx, i) {
                        final result = sources[i];
                        return GroupedSliceItem(
                          index: i,
                          count: count,
                          child: BookDetailChangeSourceItem(
                            searchBook: result,
                            chapterCount: provider.chapterCountOf(result),
                            onTap: () => _handleSelect(
                              context,
                              result,
                              provider.tocOf(result),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSelect(
    BuildContext context,
    SearchBook result,
    SourceToc? toc,
  ) async {
    if (_isSwitchingSource) return;
    if (widget.borrow != null) {
      return _openLender(
        context,
        context.read<BookDetailChangeSourceProvider>(),
        result,
        toc,
      );
    }
    setState(() => _isSwitchingSource = true);
    try {
      final select = widget.onSelectSource;
      final ChangeSourceOutcome outcome;
      if (select != null) {
        outcome = await select(result, toc);
      } else {
        final detailOutcome = await widget.detailProvider!.changeSource(
          result,
          toc: toc,
        );
        outcome = (
          success: detailOutcome.success,
          message: detailOutcome.message,
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: UiText(outcome.message)));
      if (outcome.success) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSwitchingSource = false);
    }
  }

  Widget _buildHeader(BookDetailChangeSourceProvider provider) {
    final primary = Theme.of(context).colorScheme.primary;
    return SheetHeader(
      title: widget.borrow == null ? '更換來源' : '單章借源',
      // 左右各一顆（docs/design/components.md）：兩個篩選收進一顆選單，
      // 有一項開著時圖示用強調色。
      leading: GlassMenuButton<_SourceFilter>(
        icon: Icons.filter_list_rounded,
        tooltip: '篩選',
        color: provider.checkAuthor || provider.excludeFarWordCount
            ? primary
            : null,
        enabled: !_isSwitchingSource,
        entriesBuilder: (_) => [
          GlassMenuItem(
            value: _SourceFilter.checkAuthor,
            label: '校驗作者',
            icon: Icons.person_outline_rounded,
            checked: provider.checkAuthor,
            toggle: true,
          ),
          GlassMenuItem(
            value: _SourceFilter.excludeFarWordCount,
            label: '不列字數差太多的',
            icon: Icons.straighten_rounded,
            checked: provider.excludeFarWordCount,
            toggle: true,
          ),
        ],
        onSelected: (filter) => switch (filter) {
          _SourceFilter.checkAuthor => provider.toggleCheckAuthor(),
          _SourceFilter.excludeFarWordCount =>
            provider.toggleExcludeFarWordCount(),
        },
      ),
      trailing: provider.isSearching
          ? const SizedBox.square(
              dimension: AppGlass.buttonSize,
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : GlassIconButton(
              icon: Icons.refresh_rounded,
              iconSize: 20,
              tooltip: '重新搜尋',
              onPressed: _isSwitchingSource ? null : provider.refreshSearch,
            ),
    );
  }

  /// 單章借源點了一個書源：抓好（清單沒留著時重抓）它的詳情與目錄，核對是
  /// 同一本小說，打開它的目錄、捲到估計的那一章（先比章名、再比章號，同
  /// 換源的對法）。
  Future<void> _openLender(
    BuildContext context,
    BookDetailChangeSourceProvider provider,
    SearchBook result,
    SourceToc? toc,
  ) async {
    final borrow = widget.borrow!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSwitchingSource = true);
    try {
      final source = await provider.findSourceByUrl(result.origin);
      if (source == null) {
        throw SourceException('找不到對應書源', sourceUrl: result.origin);
      }
      final loaded =
          toc ?? await loadSourceToc(BookSourceService(), source, result);
      final book = widget.originalBook;
      final lenderBook = loaded.book;
      // 聚合源的書是哪一類抓完詳情才知道；作者兩邊都寫了才比。
      if (lenderBook.bookKind != BookSourceKind.novel ||
          !isSameBook(
            lenderBook.name,
            lenderBook.author,
            book.name,
            book.author,
            checkAuthor: book.author.isNotEmpty && lenderBook.author.isNotEmpty,
          )) {
        throw SourceException('不是同一本書', sourceUrl: result.origin);
      }
      if (!mounted) return;
      setState(
        () => _lender = (
          candidate: result,
          source: source,
          toc: loaded,
          estimated: alignChapterIndex(
            oldIndex: borrow.chapter.index,
            oldTitle: borrow.chapter.title,
            oldTotalCount: book.totalChapterNum,
            newChapters: loaded.chapters,
          ),
        ),
      );
    } catch (error, stackTrace) {
      if (!isSourceSwitchUnavailable(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      messenger.showSnackBar(
        SnackBar(content: UiText(failureMessage('借源', error))),
      );
    } finally {
      if (mounted) setState(() => _isSwitchingSource = false);
    }
  }

  /// 借的書源的目錄：點一章就借（[_borrowChapter]），頁首左邊回到書源清單。
  Widget _buildLender(_Lender lender) {
    final chrome = AppChrome.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: chrome.groupedBackground,
        borderRadius: AppRadius.topSheetLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '單章借源',
            leading: GlassIconButton(
              icon: Icons.arrow_back_rounded,
              iconSize: 20,
              tooltip: '返回',
              onPressed: () {
                _borrowing?.cancel();
                setState(() => _lender = null);
              },
            ),
          ),
          SizedBox(
            height: 2,
            child: _isSwitchingSource
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppGrouped.sectionGap,
            ),
            child: GroupedSliceItem(
              index: 0,
              count: 1,
              child: BookDetailChangeSourceItem(
                searchBook: lender.candidate,
                chapterCount: lender.toc.chapters.length,
              ),
            ),
          ),
          Expanded(
            child: IgnorePointer(
              ignoring: _isSwitchingSource,
              child: BorrowChapterToc(
                chapters: lender.toc.chapters,
                estimated: lender.estimated,
                onPick: (index) => unawaited(_borrowChapter(lender, index)),
                onLocked: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: UiText(lockedChapterNotice)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 借 [lender] 目錄的第 [index] 章。借成了收起面板；借的書源要登入或網頁
  /// 驗證時提示旁給「登入」「前往驗證」，開的是借的書源，回來重借同一章
  /// （ADR 0038）。
  Future<void> _borrowChapter(_Lender lender, int index) async {
    if (_isSwitchingSource) return;
    final messenger = ScaffoldMessenger.of(context);
    final cancelToken = _borrowing = CancelToken();
    setState(() => _isSwitchingSource = true);
    try {
      await widget.borrow!.borrowFrom(
        lender.source,
        lender.toc,
        index,
        cancelToken,
      );
      if (mounted) Navigator.pop(context);
    } catch (error, stackTrace) {
      if (cancelToken.isCancelled || !mounted) return;
      if (!isSourceSwitchUnavailable(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      final message = failureMessage('借源', error);
      messenger.showSnackBar(
        SnackBar(
          content: UiText(message),
          action: _remedyFor(lender, index, message),
        ),
      );
    } finally {
      if (identical(_borrowing, cancelToken)) _borrowing = null;
      if (mounted) setState(() => _isSwitchingSource = false);
    }
  }

  SnackBarAction? _remedyFor(_Lender lender, int index, String message) {
    final source = lender.source;
    void retry() {
      if (mounted && identical(_lender, lender)) {
        unawaited(_borrowChapter(lender, index));
      }
    }

    if (SourceVerificationException.describes(message)) {
      final request = SourceInteraction.verificationFor(source.bookSourceUrl);
      if (request == null) return null;
      return SnackBarAction(
        label: '前往驗證',
        onPressed: () async {
          await openSourceVerification(
            context,
            sourceUrl: source.bookSourceUrl,
            sourceName: source.bookSourceName,
            request: request,
          );
          retry();
        },
      );
    }
    if (LoginCheckException.describes(message) && source.hasLogin) {
      return SnackBarAction(
        label: '登入',
        onPressed: () async {
          if (await openSourceLogin(context, source)) retry();
        },
      );
    }
    return null;
  }
}
