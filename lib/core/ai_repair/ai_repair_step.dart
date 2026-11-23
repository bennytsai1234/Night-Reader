/// 一步的狀態：還沒開始、做著、做完、失敗。
enum AiRepairStepState { waiting, running, done, failed }

/// 修復的固定幾段：修復頁一段一列，AI 的輪併成中間的「AI 修改規則」；從空白
/// 建立書源是「檢查網站、抓貼的網頁、AI 寫規則、校驗寫好的書源」。
const String aiRepairCheckStage = '校驗原本的書源';
const String aiRepairFetchStage = '抓網頁';
const String aiRepairVerifyStage = '校驗修好的書源';
const String aiCreateSiteStage = '檢查網站';
const String aiCreateFetchStage = '抓貼的網頁';
const String aiCreateWriteStage = 'AI 寫規則';
const String aiCreateVerifyStage = '校驗寫好的書源';

/// 一步是哪一種：固定的一段（校驗、抓網頁）、AI 的一輪，或換一段新的對話
/// 重新開始。修復頁把後兩種併成「AI 修改規則」一段，過程收在「經過」裡
/// （docs/design/screens.md「AI 修書源」）。
enum AiRepairStepKind { stage, round, restart }

/// 修復過程的一步。
class AiRepairStep {
  AiRepairStep(
    this.title, {
    this.detail,
    this.state = AiRepairStepState.running,
    this.kind = AiRepairStepKind.stage,
  });

  /// 固定的一段是頁面上的標題；AI 的一輪是紀錄裡的段名（「第 3 輪」），
  /// 頁面不顯示。
  final String title;

  /// AI 的一輪是它在做的事（「看網頁 網址…」「AI 改了搜尋，試抓：…」），
  /// 其他是這一步的結果。
  String? detail;
  AiRepairStepState state;
  final AiRepairStepKind kind;

  /// 寫成一句：AI 的一輪是它在做的事，重新開始寫原因，其他是「標題：結果」。
  /// 通知內文與整批修復「正在修」的副標用它。
  String get line => switch (kind) {
    AiRepairStepKind.round => detail ?? '',
    AiRepairStepKind.restart => '重新開始：${detail ?? ''}',
    AiRepairStepKind.stage => detail == null ? title : '$title：$detail',
  };

  /// 存成暫停的工作（背景工作接著做，ADR 0058）。
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': ?detail,
    'state': state.name,
    'kind': kind.name,
  };

  /// 存檔沒寫種類時當成 [kind]。
  factory AiRepairStep.fromJson(
    Object? json, {
    AiRepairStepKind kind = AiRepairStepKind.stage,
  }) {
    if (json case {'title': final String title}) {
      return AiRepairStep(
        title,
        detail: switch (json['detail']) {
          final String detail => detail,
          _ => null,
        },
        state: AiRepairStepState.values.firstWhere(
          (state) => state.name == json['state'],
          orElse: () => AiRepairStepState.done,
        ),
        kind: AiRepairStepKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => kind,
        ),
      );
    }
    throw const FormatException('一步的格式不對');
  }
}
