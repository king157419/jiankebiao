import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/features/import/web/edu_session.dart';
import 'package:shu_schedule/features/import/web/external_navigation.dart';
import 'package:shu_schedule/models/app_settings.dart';

class _FakeStore implements EduSessionStore {
  _FakeStore({this.cookieError, this.storageHangs = false});

  final Object? cookieError;
  final bool storageHangs;
  int cookieCalls = 0;
  int storageCalls = 0;

  @override
  Future<void> clearCookies() async {
    cookieCalls++;
    if (cookieError != null) throw cookieError!;
  }

  @override
  Future<void> clearLocalStorage() {
    storageCalls++;
    if (storageHangs) return Completer<void>().future;
    return Future<void>.value();
  }
}

void main() {
  group('清理策略 shouldClearEduSession', () {
    test('默认（不记住）：导入成功、离开登录页都清', () {
      for (final e in <EduSessionEvent>[
        EduSessionEvent.importSucceeded,
        EduSessionEvent.loginPageClosed,
      ]) {
        expect(shouldClearEduSession(rememberLogin: false, event: e), isTrue);
      }
    });

    test('记住教务登录：导入成功、离开登录页都不清', () {
      for (final e in <EduSessionEvent>[
        EduSessionEvent.importSucceeded,
        EduSessionEvent.loginPageClosed,
      ]) {
        expect(shouldClearEduSession(rememberLogin: true, event: e), isFalse);
      }
    });

    test('关掉「记住教务登录」时无条件清一次', () {
      expect(
        shouldClearEduSession(
          rememberLogin: true,
          event: EduSessionEvent.rememberTurnedOff,
        ),
        isTrue,
      );
    });
  });

  group('clearEduSessionIfNeeded', () {
    test('需要清时 Cookie 与网页存储都清', () async {
      final store = _FakeStore();
      final r = await clearEduSessionIfNeeded(
        rememberLogin: false,
        event: EduSessionEvent.importSucceeded,
        store: store,
      );
      expect(r!.ok, isTrue);
      expect(store.cookieCalls, 1);
      expect(store.storageCalls, 1);
    });

    test('记住登录时一个都不碰，返回 null', () async {
      final store = _FakeStore();
      final r = await clearEduSessionIfNeeded(
        rememberLogin: true,
        event: EduSessionEvent.importSucceeded,
        store: store,
      );
      expect(r, isNull);
      expect(store.cookieCalls, 0);
      expect(store.storageCalls, 0);
    });

    test('一步抛异常 / 一步超时：不抛给调用方，另一步照常执行', () async {
      final store = _FakeStore(
        cookieError: StateError('no platform'),
        storageHangs: true,
      );
      final r = await clearEduSessionIfNeeded(
        rememberLogin: false,
        event: EduSessionEvent.loginPageClosed,
        store: store,
        timeout: const Duration(milliseconds: 20),
      );
      expect(r!.cookiesCleared, isFalse);
      expect(r.storageCleared, isFalse);
      expect(r.ok, isFalse);
      expect(store.storageCalls, 1, reason: 'Cookie 失败不能挡住清网页存储');
    });
  });

  group('AppSettings.rememberEduLogin', () {
    test('默认 false；旧存档没有这个字段 → false', () {
      expect(AppSettings.defaults().rememberEduLogin, isFalse);
      final old = AppSettings.fromJson(<String, dynamic>{
        'currentTimetableId': 'a',
        'themeId': 'default',
        'showNonCurrentWeekCourses': true,
        'showTimeInGrid': true,
        'settingsVersion': 2,
      });
      expect(old.rememberEduLogin, isFalse);
      expect(old.showTimeInGrid, isTrue, reason: '加字段不影响已有迁移');
    });

    test('JSON 往返；类型不对当 false', () {
      final s = AppSettings.defaults().copyWith(rememberEduLogin: true);
      final back = AppSettings.fromJson(s.toJson());
      expect(back.rememberEduLogin, isTrue);
      expect(
        AppSettings.fromJson(<String, dynamic>{'rememberEduLogin': 'yes'})
            .rememberEduLogin,
        isFalse,
      );
    });
  });

  group('WebView 跳转分流 planNavigation', () {
    test('http(s) / about / data / blob / 相对地址交给 WebView', () {
      for (final url in <String>[
        'https://jwxt.shu.edu.cn/jwglxt/',
        'http://newsso.shu.edu.cn/login',
        'HTTPS://A.EDU.CN/',
        'about:blank',
        'data:text/html,hi',
        'blob:https://a.edu.cn/uuid',
        '/relative/path',
      ]) {
        expect(planNavigation(url).kind, NavigationKind.web, reason: url);
      }
    });

    test('企业微信 / 微信 / QQ 等自定义 scheme → 交给外部 App', () {
      for (final url in <String>[
        'wxwork://auth?appid=x&state=y',
        'weixin://dl/business/?t=abc',
        'mqqapi://forward/url?src_type=web',
        'alipays://platformapi/startapp',
      ]) {
        final plan = planNavigation(url);
        expect(plan.kind, NavigationKind.external, reason: url);
        expect(plan.externalUri.toString(), url);
        expect(plan.fallbackUrl, isNull);
      }
    });

    test('intent:// → 换成真实 scheme，并带上 browser_fallback_url', () {
      final plan = planNavigation(
        'intent://auth/login?code=1#Intent;scheme=wxwork;package=com.tencent.wework;'
        'S.browser_fallback_url=https%3A%2F%2Fwork.weixin.qq.com%2Fwework_admin%2Floginpage;end',
      );
      expect(plan.kind, NavigationKind.external);
      expect(plan.externalUri.toString(), 'wxwork://auth/login?code=1');
      expect(
        plan.fallbackUrl.toString(),
        'https://work.weixin.qq.com/wework_admin/loginpage',
      );
    });

    test('intent:// 只有 fallback / 什么都没有', () {
      final onlyFallback = planNavigation(
        'intent://x#Intent;S.browser_fallback_url=https%3A%2F%2Fa.edu.cn%2F;end',
      );
      expect(onlyFallback.kind, NavigationKind.external);
      expect(onlyFallback.externalUri, isNull);
      expect(onlyFallback.fallbackUrl.toString(), 'https://a.edu.cn/');

      expect(
        planNavigation('intent://x#Intent;end').kind,
        NavigationKind.block,
      );
      expect(
        planNavigation(
          'intent://x#Intent;scheme=weixin;S.browser_fallback_url=javascript%3Aalert(1);end',
        ).fallbackUrl,
        isNull,
        reason: 'fallback 只接受 http(s)',
      );
    });

    test('空地址 / file / content 直接拦下，不交给外部', () {
      expect(planNavigation('').kind, NavigationKind.block);
      expect(
        planNavigation('file:///sdcard/a.html').kind,
        NavigationKind.block,
      );
      expect(
        planNavigation('content://com.android.contacts/x').kind,
        NavigationKind.block,
      );
    });
  });
}
