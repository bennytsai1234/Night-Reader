import 'package:night_reader/features/reader_v2/session/reader_v2_operation_token.dart';

/// 閱讀器的紙（[LoadingVeilController]）現在歸誰管：誰決定紙什麼時候掀開、
/// 交給誰。紙蓋上、蓋滿、掀開的樣子由 [LoadingVeilController] 管；這裡只管
/// 歸屬。
///
/// 會管紙的有三種，可能同時成立：
///
/// - **等正文的跳章**（[jump]）：跳章一開始就蓋紙，正文還在取得時舊正文不留
///   在畫面上；紙下的舊正文歸它，翻頁、自動捲動與朗讀跟隨都不能動它，離開時
///   也不記下這一頁。排版開始（[restoreTookOverJump]）後交給還原。
/// - **進行中的還原**（[restoring]）：開書、跳章、改排版、重載內容、重新定位
///   都經過它。它在取正文時，跳章也還算數。結束時由它決定掀紙或交出去。
/// - **重新還原最後的穩定位置**（[restoringStableWorld]）：沒有操作負責、正文
///   卻不在畫面上或已經過時時，由畫面自己發起；裡面還會包一次還原。
///
/// 三者都沒有、Runtime 也沒有進行中的操作時紙沒人用（[isFree]），才由畫面
/// 掀紙或重新還原。原本這三件事是畫面上的三個欄位，靠三個函式互相補位
/// （跳章蓋紙、#59；開書時跳章、#80）。
final class PaperOwners {
  ReaderV2OperationToken? _jump;
  bool Function()? _restore;
  bool _stableWorld = false;

  /// 正在等正文的跳章；排版開始後或跳章結束時為 null。
  ReaderV2OperationToken? get jump => _jump;

  /// 有跳章在等正文：紙下的舊正文歸它，不能被移動或記下。
  bool get holdsTextForJump => _jump != null;

  /// 有還原正在進行而且還有效（被取代的還原不算）。
  bool get restoring => _restore?.call() ?? false;

  /// 正在重新還原最後的穩定位置。
  bool get restoringStableWorld => _stableWorld;

  /// 紙沒人用：沒有進行中的操作（[hasOperation]）、還原與重新還原。
  bool isFree({required bool hasOperation}) =>
      !hasOperation && !restoring && !_stableWorld;

  /// Runtime 目前的操作換成了 [operation]：是跳章就由它蓋紙（回傳 true，呼叫端
  /// 蓋紙）。[textShown] 是正文已經排好、畫在畫面上；開書還沒排好時跳章不另外
  /// 蓋紙，紙本來就蓋著。同一個跳章重複通知不重來。
  bool claimForJump(
    ReaderV2OperationToken? operation, {
    required bool textShown,
  }) {
    if (identical(operation, _jump)) return false;
    _jump = null;
    if (operation == null || !textShown) return false;
    _jump = operation;
    return true;
  }

  /// 排版流程開始接手這張紙（正文取到、開始排第一頁或重排），等正文的跳章
  /// 不再另外管它。
  void restoreTookOverJump() => _jump = null;

  /// 一次還原開始；[isCurrent] 為 false 時這次還原已經作廢。
  void beginRestore(bool Function() isCurrent) => _restore = isCurrent;

  /// [isCurrent] 那次還原結束；之後已經有更新的還原開始時不影響它。
  void endRestore(bool Function() isCurrent) {
    if (identical(_restore, isCurrent)) _restore = null;
  }

  /// 開始重新還原最後的穩定位置；已經在進行時回傳 false。
  bool beginStableWorld() {
    if (_stableWorld) return false;
    _stableWorld = true;
    return true;
  }

  void endStableWorld() => _stableWorld = false;
}
