import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/services/app_permission_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 隱私說明：App 在本機與網路上處理哪些資料。從「關於夜讀」進來。
class PrivacyNoticePage extends StatelessWidget {
  const PrivacyNoticePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '隱私說明'),
      body: GroupedListView(
        children: _noticeSections(context, const [
          _NoticeSection(
            title: '本地資料',
            body: '書架、書源、章節、正文快取（含正文裡的插圖）、下載的漫畫圖、閱讀進度、書籤、標註、閱讀設定、替換規則與 TTS 設定會保存在本機資料庫或本機偏好設定中。',
          ),
          _NoticeSection(
            title: 'Cookie 與 WebView',
            body: '需要登入或驗證的書源可能會保存 Cookie。WebView 書源可能會產生 Cookie、localStorage 與網頁快取，可在「關於夜讀」的「清除網頁資料」清除。',
          ),
          _NoticeSection(
            title: '網路請求',
            body: '搜尋、詳情、目錄、正文與正文裡的插圖、漫畫的圖、封面與書源驗證會向使用者配置的書源或網址發出請求，請求可能包含 User-Agent、Headers 與 Cookie。選了思源宋體或霞鶩文楷當字型時，會從 GitHub 下載一次字型檔，請求不帶任何個人資料。',
          ),
          _NoticeSection(
            title: 'AI 修書源',
            body: '在書源管理按「AI 修復」時，會把這個書源的 JSON、一次書源校驗的結果、試抓時每個網頁的開頭一段（每頁最多 3000 字）與除錯紀錄，送到使用者在「AI 修書源設定」填的服務，用使用者的金鑰與模型；AI 要求再試抓時，送那一次的結果。登入資料、Cookie 與書源變數不送。試抓的網頁可能含網站上的個人化內容。沒有設定 AI 服務時，「複製給 AI」把同樣的內容複製到剪貼簿。AI 改書源之前的那一份只存在這台手機，用來還原。',
          ),
          _NoticeSection(
            title: '備份資料',
            body: '備份檔會包含書架、書源、閱讀進度、書籤、標註、設定、規則與已快取正文等資料，以及書源的登入資料（登入表單填的帳號密碼、登入標頭與 Cookie）與 AI 修書源設定（服務網址、金鑰、模型）。正文裡的插圖、下載的漫畫圖與本地書的原檔不在備份裡；還原後，網路書的插圖與漫畫會照書架自動下載重新抓。備份檔目前不加密，請自行保存於可信位置。',
          ),
          _NoticeSection(
            title: '同步',
            body: '設定了同步空間（Google 雲端硬碟或 WebDAV）時，書架上的書（書名、作者、書源網址、自訂的封面與簡介）、閱讀進度（讀到第幾章第幾個字）、書籤（留在哪一句與那一句的字）、標註（畫到的字、在哪一章、顏色與備忘）、書源、替換規則、閱讀與外觀設定、閱讀統計（每本書讀了多久）、書源的登入資料（登入表單填的內容、登入後的身分資料與網站的 Cookie），以及 AI 修書源設定（服務網址、金鑰、模型）會存到使用者自己的同步空間，不經過其他伺服器。按「同步本地書」時，書架上本地書（TXT、EPUB）的原檔與本地漫畫的每一話（CBZ），與它的書名、作者、檔案大小、章名也會存到同步空間。Google 雲端硬碟只用夜讀專屬的隱藏資料夾，讀不到雲端硬碟裡的其他檔案；這台手機只記下登入的 Google 帳號（電子郵件），授權由 Google Play 服務保管。WebDAV 的帳號密碼存在這台手機的設定裡，備份檔也會帶著。同步的資料不加密。',
          ),
          _NoticeSection(
            title: 'Crash log',
            body: 'Crash log 用於除錯，可能包含錯誤訊息、網址或書源解析資訊。App 不會自動上傳這些 log。',
          ),
        ]),
      ),
    );
  }
}

/// 權限：上面是目前的權限狀態（可以直接要求或開系統設定），下面是每一種
/// 權限拿來做什麼。從「關於夜讀」進來。
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key, this.service});

  /// 允許測試用可控制的權限查詢，正式頁面使用系統實作。
  final AppPermissionService? service;

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage>
    with WidgetsBindingObserver {
  late final AppPermissionService _permissionService =
      widget.service ?? AppPermissionService();
  late Future<AppPermissionSnapshot> _permissionSnapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissionSnapshot = _permissionService.loadSnapshot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 從系統設定改完權限回來時重新讀取狀態。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissionSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '權限'),
      body: FutureBuilder<AppPermissionSnapshot>(
        future: _permissionSnapshot,
        builder: (context, snapshot) => GroupedListView(
          // 等狀態查完才揭開：骨架先有固定的權限列，換場前改用查到的
          // 真正狀態排字與箭頭；重查時 FutureBuilder 保留上次資料。
          ready: snapshot.hasData || snapshot.hasError,
          children: [
            _buildPermissionSection(snapshot),
            ..._noticeSections(context, const [
              _NoticeSection(
                title: '檔案',
                body: '匯入本地書、匯入/匯出書源、建立備份與從備份檔還原會透過系統檔案選擇器或分享面板讀取、建立檔案。App 只處理使用者選取或分享的檔案，不要求 Android 所有檔案存取權。',
              ),
              _NoticeSection(
                title: '網路',
                body: '網路權限用於搜尋書籍、載入章節、下載封面、同步 Cookie、多台手機同步、WebView 驗證與書源除錯。',
              ),
              _NoticeSection(
                title: '通知與背景任務',
                body: 'TTS 朗讀的媒體控制會使用通知權限；若使用者拒絕，朗讀仍可執行，但通知列控制可能無法顯示。背景任務會受到系統省電與背景執行設定限制。',
              ),
              _NoticeSection(
                title: '相簿',
                body: '更換書籍封面時可能會開啟系統圖片選取器。iOS 會顯示相簿權限提示，Android 以系統圖片選取流程為主，不要求整個相簿或儲存空間存取權。',
              ),
              _NoticeSection(
                title: 'WebView',
                body: '部分書源會使用 WebView 載入網頁、執行必要腳本或完成驗證。WebView 可能產生 Cookie、localStorage 與 cache。',
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionSection(
    AsyncSnapshot<AppPermissionSnapshot> snapshot,
  ) {
    if (snapshot.hasError) {
      return GroupedSection(
        header: '權限狀態',
        children: [
          GroupedRow(
            title: '權限狀態載入失敗',
            subtitle: userErrorReason(snapshot.error!),
            maxSubtitleLines: 4,
            value: '重試',
            showChevron: false,
            onTap: _refreshPermissionSnapshot,
          ),
        ],
      );
    }

    final items =
        snapshot.data?.items ?? _permissionService.loadingSnapshot().items;
    return GroupedSection(
      header: '權限狀態',
      children: [
        for (final item in items) _permissionRow(item),
        GroupedRow(
          title: '開啟系統設定',
          accent: true,
          showChevron: false,
          onTap: _permissionService.openSystemSettings,
        ),
        GroupedRow(
          title: '重新整理',
          accent: true,
          showChevron: false,
          onTap: _refreshPermissionSnapshot,
        ),
      ],
    );
  }

  Widget _permissionRow(AppPermissionItem item) {
    final color = _permissionColor(item.tone);
    return GroupedRow(
      // 與圖示方塊同寬，分隔線才會對齊文字起點。
      leading: SizedBox(
        width: AppGrouped.iconTile,
        child: Icon(_permissionIcon(item.tone), color: color, size: 24),
      ),
      title: item.title,
      showChevron: item.action != null,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 112),
        child: Text(
          item.status,
          textAlign: TextAlign.end,
          style: AppTextStyles.uiSm.copyWith(
            height: 1.3,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      onTap: item.action == null ? null : () => _handlePermissionTap(item),
    );
  }

  Future<void> _handlePermissionTap(AppPermissionItem item) async {
    switch (item.action) {
      case AppPermissionAction.openSettings:
        // 回到 App 時由 didChangeAppLifecycleState 重新讀取。
        await _permissionService.openSystemSettings();
      case AppPermissionAction.request:
        await _permissionService.request(item.target!);
        _refreshPermissionSnapshot();
      case null:
        return;
    }
  }

  void _refreshPermissionSnapshot() {
    if (!mounted) return;
    setState(() {
      _permissionSnapshot = _permissionService.loadSnapshot();
    });
  }

  IconData _permissionIcon(AppPermissionStatusTone tone) {
    switch (tone) {
      case AppPermissionStatusTone.ok:
        return Icons.check_circle_outline;
      case AppPermissionStatusTone.attention:
        return Icons.info_outline;
      case AppPermissionStatusTone.blocked:
        return Icons.block;
      case AppPermissionStatusTone.neutral:
        return Icons.radio_button_unchecked;
    }
  }

  Color _permissionColor(AppPermissionStatusTone tone) {
    final scheme = Theme.of(context).colorScheme;
    switch (tone) {
      case AppPermissionStatusTone.ok:
        return context.success;
      case AppPermissionStatusTone.attention:
        return scheme.primary;
      case AppPermissionStatusTone.blocked:
        return scheme.error;
      case AppPermissionStatusTone.neutral:
        return AppChrome.of(context).sectionText;
    }
  }
}

List<Widget> _noticeSections(
  BuildContext context,
  List<_NoticeSection> sections,
) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return [
    for (final section in sections)
      GroupedSection(
        header: section.title,
        children: [
          GroupedContent(
            padding: const EdgeInsets.symmetric(
              horizontal: AppGrouped.rowPadding,
              vertical: AppSpacing.lg,
            ),
            child: Text(
              section.body,
              style: AppTextStyles.bodyBase.copyWith(
                height: 1.55,
                color: onSurface,
              ),
            ),
          ),
        ],
      ),
  ];
}

class _NoticeSection {
  const _NoticeSection({required this.title, required this.body});

  final String title;
  final String body;
}
