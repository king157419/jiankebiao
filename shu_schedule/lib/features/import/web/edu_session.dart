import 'dart:async';

import 'package:webview_flutter/webview_flutter.dart';

/// 什么时候考虑清理教务登录态。
enum EduSessionEvent {
  /// 用户在预览页确认导入、课表已写入。
  importSucceeded,

  /// 用户离开了教务登录页（没导入就关掉 / 导入失败后返回）。
  loginPageClosed,

  /// 用户在设置里关掉了「记住教务登录」。
  rememberTurnedOff,
}

/// 清理策略（纯函数）：
/// - 关掉「记住教务登录」时，不管之前怎样都立刻清一次；
/// - 其余时机：没开「记住教务登录」（默认）就清，开了就保留。
bool shouldClearEduSession({
  required bool rememberLogin,
  required EduSessionEvent event,
}) {
  if (event == EduSessionEvent.rememberTurnedOff) return true;
  return !rememberLogin;
}

/// 能清理 WebView 登录态的东西。抽出来是为了在测试里换成假的。
abstract class EduSessionStore {
  /// 清掉所有 Cookie（WebView 全局）。
  Future<void> clearCookies();

  /// 清掉 localStorage / sessionStorage / IndexedDB 等网页存储（WebView 全局）。
  Future<void> clearLocalStorage();
}

/// 真实实现：`WebViewCookieManager` + `WebViewController.clearLocalStorage`。
///
/// Android 上两者都是全局的（`CookieManager.removeAllCookies` /
/// `WebStorage.deleteAllData`），所以随便用哪个 controller 都能清；
/// 没有现成 controller 时（例如设置页）临时建一个。
class WebViewEduSessionStore implements EduSessionStore {
  WebViewEduSessionStore({this.controller});

  /// 现成的 controller；null 时临时建一个。
  final WebViewController? controller;

  @override
  Future<void> clearCookies() async {
    await WebViewCookieManager().clearCookies();
  }

  @override
  Future<void> clearLocalStorage() async {
    await (controller ?? WebViewController()).clearLocalStorage();
  }
}

/// 清理结果。
class EduSessionClearResult {
  final bool cookiesCleared;
  final bool storageCleared;

  const EduSessionClearResult({
    required this.cookiesCleared,
    required this.storageCleared,
  });

  bool get ok => cookiesCleared && storageCleared;
}

/// 按策略清理教务登录态。两步互不影响：一步失败 / 超时不会挡住另一步，
/// 也不会把异常抛给调用方（导入已经成功了，不能因为清 Cookie 失败而报错）。
Future<EduSessionClearResult?> clearEduSessionIfNeeded({
  required bool rememberLogin,
  required EduSessionEvent event,
  required EduSessionStore store,
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (!shouldClearEduSession(rememberLogin: rememberLogin, event: event)) {
    return null;
  }
  Future<bool> attempt(Future<void> Function() step) async {
    try {
      await step().timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  final cookies = await attempt(store.clearCookies);
  final storage = await attempt(store.clearLocalStorage);
  return EduSessionClearResult(
    cookiesCleared: cookies,
    storageCleared: storage,
  );
}
