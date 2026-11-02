import 'package:google_sign_in/google_sign_in.dart';

import 'sync_store.dart';

/// 用 Google 帳號取 Google 雲端硬碟的授權（ADR 0039）。只要 App 專屬的隱藏
/// 資料夾（`drive.appdata`），Google 歸為不敏感的權限，看不到使用者其他檔案。
abstract interface class GoogleDriveAuth {
  /// 跳出 Google 登入與授權畫面，傳回登入的帳號（電子郵件）。只在使用者按了
  /// 按鈕時呼叫。
  Future<String> signIn();

  /// 不跳畫面取一個 access token；授權失效（使用者在 Google 帳號撤銷了）時
  /// 丟 [SyncStoreException]。
  Future<String> token();

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

  static const String serverClientId = '';

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
      throw SyncStoreException(switch (error.code) {
        GoogleSignInExceptionCode.canceled => '沒有登入 Google 帳號',
        _ => 'Google 登入失敗：${error.description ?? error.code.name}',
      });
    }
  }

  @override
  Future<String> token() async {
    await _ensureInitialized();
    final GoogleSignInClientAuthorization? authorization;
    try {
      authorization = await GoogleSignIn.instance.authorizationClient
          .authorizationForScopes(const [scope]);
    } on GoogleSignInException catch (error) {
      throw SyncStoreException(
        'Google 授權失敗：${error.description ?? error.code.name}',
      );
    }
    if (authorization == null) {
      throw const SyncStoreException('Google 帳號的授權失效了，到「同步空間」重新登入');
    }
    return authorization.accessToken;
  }

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
