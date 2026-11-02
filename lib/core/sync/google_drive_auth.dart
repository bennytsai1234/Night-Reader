import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'sync_store.dart';

/// 用 Google 帳號取 Google 雲端硬碟的授權（ADR 0039）。只要 App 專屬的隱藏
/// 資料夾（`drive.appdata`），Google 歸為不敏感的權限，看不到使用者其他檔案。
abstract interface class GoogleDriveAuth {
  /// 跳出 Google 登入與授權畫面，傳回登入的帳號（電子郵件）。只在使用者按了
  /// 按鈕時呼叫。
  Future<String> signIn();

  /// 不跳畫面取 [account] 這個帳號的 access token；這個帳號的授權失效（使用者
  /// 在 Google 帳號撤銷了、手機上移除了這個帳號）時丟 [SyncStoreException]。
  Future<String> token(String account);

  /// 這個 token 被 Google 拒絕了，丟掉，下次 [token] 重新取。
  Future<void> forget(String token);

  /// 停用同步：登出 Google 帳號。
  Future<void> signOut();
}

/// 走 Android 的 Google 登入（`google_sign_in`）。用戶端編號在 Google Cloud
/// 的「Night Reader Sync」專案（night-reader-sync）：Android 用的那個登記了
/// 套件名與正式簽章指紋，不用寫在程式裡；[serverClientId] 是網頁用的那個，
/// Android 的登入一定要給。
class GoogleSignInDriveAuth implements GoogleDriveAuth {
  GoogleSignInDriveAuth._();

  static final GoogleSignInDriveAuth instance = GoogleSignInDriveAuth._();

  static const String scope = 'https://www.googleapis.com/auth/drive.appdata';

  static const String serverClientId =
      '856780370145-u1dj6opn9ov8flr3r96id19h3k5ukg9s.apps.googleusercontent.com';

  Future<void>? _initialized;

  Future<void> _ensureInitialized() => _initialized ??= GoogleSignIn.instance
      .initialize(serverClientId: serverClientId);

  @override
  Future<String> signIn() async {
    await _ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [scope],
      );
      await account.authorizationClient.authorizeScopes(const [scope]);
      return account.email;
    } on GoogleSignInException catch (error) {
      throw SyncStoreException(_message('Google 登入失敗', error));
    }
  }

  /// 指定帳號取授權：手機上有好幾個 Google 帳號時，`google_sign_in` 不指定
  /// 帳號的入口可能拿到另一個帳號的 token，讀寫到另一個帳號的雲端硬碟。
  /// 綁帳號的入口（`GoogleSignInAccount.authorizationClient`）只在登入當下
  /// 拿得到，所以背景直接照它的做法帶上帳號問平台。
  @override
  Future<String> token(String account) async {
    await _ensureInitialized();
    final ClientAuthorizationTokenData? authorization;
    try {
      authorization = await GoogleSignInPlatform.instance
          .clientAuthorizationTokensForScopes(
            ClientAuthorizationTokensForScopesParameters(
              request: AuthorizationRequestDetails(
                scopes: const [scope],
                userId: null,
                email: account,
                promptIfUnauthorized: false,
              ),
            ),
          );
    } on GoogleSignInException catch (error) {
      throw SyncStoreException(_message('Google 授權失敗', error));
    }
    if (authorization == null) {
      throw const SyncStoreException('Google 帳號的授權失效了，到「同步空間」重新登入');
    }
    return authorization.accessToken;
  }

  static String _message(String failed, GoogleSignInException error) =>
      switch (error.code) {
        GoogleSignInExceptionCode.canceled => '沒有登入 Google 帳號',
        GoogleSignInExceptionCode.interrupted => 'Google 登入被中斷了，再試一次',
        GoogleSignInExceptionCode.providerConfigurationError =>
          '這台手機用不了 Google 登入，確認 Google Play 服務，或改用 WebDAV',
        GoogleSignInExceptionCode.userMismatch =>
          'Google 帳號和同步空間記的不同，到「同步空間」重新登入',
        _ => '$failed：${error.description ?? error.code.name}',
      };

  @override
  Future<void> forget(String token) async {
    await _ensureInitialized();
    await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
      accessToken: token,
    );
  }

  @override
  Future<void> signOut() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
  }
}
