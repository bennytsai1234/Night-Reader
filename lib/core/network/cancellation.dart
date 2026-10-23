import 'package:dio/dio.dart';

/// 等 [work] 完成；[cancelToken] 先取消時不再等，丟出取消。[work] 本身沒辦
/// 法中途停下，會照樣跑完，結果與錯誤丟掉：只給跑完也不寫任何東西的工作
/// 用（例如交給主 isolate 的 WebView 渲染、借書源限流的名額）。
Future<T> untilCancelled<T>(Future<T> work, CancelToken? cancelToken) async {
  if (cancelToken == null) return work;
  final cancelled = Object();
  final first = await Future.any<Object?>([
    work,
    cancelToken.whenCancel.then((_) => cancelled),
  ]);
  if (!identical(first, cancelled)) return first as T;
  work.ignore();
  throw cancelToken.cancelError!;
}
