import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/app.dart';
import 'package:shu_schedule/core/app_brand.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/device_diagnostics.dart';
import 'package:shu_schedule/core/native_bridge.dart';
import 'package:shu_schedule/core/privacy_policy.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/features/settings/feedback_dialog.dart';
import 'package:shu_schedule/features/settings/privacy_page.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';
import 'package:shu_schedule/models/app_settings.dart';

import 'helpers/harness.dart';

/// v1.3.0 Phase C.1 / C.5 / C.6：品牌、隐私说明、启动时自动检查更新、检查更新入口、反馈。
///
/// v1.5.0：删掉了首次启动的隐私同意框和 `AppSettings.privacyAcceptedVersion`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------ 品牌

  group('品牌', () {
    test('AppBrand 与 strings.xml 的 app_name 一致，Manifest / 小组件都引用它', () {
      expect(AppBrand.name, '简课表');
      expect(AppBrand.slug, 'jiankebiao');
      final strings = File('android/app/src/main/res/values/strings.xml')
          .readAsStringSync();
      expect(
        strings,
        contains('<string name="app_name">${AppBrand.name}</string>'),
      );
      expect(
        strings,
        contains('<string name="widget_day_label">@string/app_name</string>'),
      );
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('android:label="@string/app_name"'));
    });

    test('lib/ 与 Android 资源里没有「上大 / 上海大学」（内置学校清单兜底除外）', () {
      final offenders = <String>[];
      final pattern = RegExp('上大|上海大学');
      final roots = <String>['lib', 'android/app/src/main/res'];
      for (final root in roots) {
        for (final f in Directory(
          root,
        ).listSync(recursive: true).whereType<File>()) {
          final path = f.path.replaceAll(r'\', '/');
          if (!(path.endsWith('.dart') || path.endsWith('.xml'))) continue;
          // schools.json 的内置兜底副本（上大是唯一的已验证学校），按约定保留。
          if (path.endsWith('import/adapters/school_registry.dart')) continue;
          final lines = f.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (pattern.hasMatch(lines[i])) {
              offenders.add('$path:${i + 1}: ${lines[i].trim()}');
            }
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });

  // ------------------------------------------------------------ 设置迁移

  group('AppSettings 新字段', () {
    test('1.2.0 的 settings.json（没有新字段）→ 没检查过更新', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'currentTimetableId': 'a',
        'themeId': 'mint',
        'showTimeInGrid': true,
        'settingsVersion': 2,
      });
      expect(s.lastUpdateCheck, isNull);
      expect(s.showTimeInGrid, isTrue);
    });

    test('JSON 往返；脏数据容错', () {
      final s = AppSettings(lastUpdateCheck: DateTime(2026, 9, 23, 8, 30));
      final back = AppSettings.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.lastUpdateCheck, DateTime(2026, 9, 23, 8, 30));
      final dirty = AppSettings.fromJson(<String, dynamic>{
        'lastUpdateCheck': 'not a date',
      });
      expect(dirty.lastUpdateCheck, isNull);
    });

    test(
      'v1.3.0–v1.4.0 的 settings.json 带 privacyAcceptedVersion：照常读出，写回时不再带这个键',
      () {
        final old = <String, dynamic>{
          'currentTimetableId': 'tt-1',
          'themeId': 'mint',
          'showNonCurrentWeekCourses': true,
          'showTimeInGrid': false,
          'rememberEduLogin': true,
          'privacyAcceptedVersion': 2,
          'lastUpdateCheck': '2026-10-07T08:30:00.000',
          'lastHolidayRefresh': '2026-10-07T08:30:05.000',
          'reminders': <String, dynamic>{'enabled': true},
          'settingsVersion': 2,
        };
        final s = AppSettings.fromJson(
          jsonDecode(jsonEncode(old)) as Map<String, dynamic>,
        );
        expect(s.currentTimetableId, 'tt-1');
        expect(s.themeId, 'mint');
        expect(s.showNonCurrentWeekCourses, isTrue);
        expect(s.rememberEduLogin, isTrue);
        expect(s.lastUpdateCheck, DateTime(2026, 10, 7, 8, 30));
        expect(s.lastHolidayRefresh, DateTime(2026, 10, 7, 8, 30, 5));
        expect(s.reminders.enabled, isTrue);
        final json = s.toJson();
        expect(json.containsKey('privacyAcceptedVersion'), isFalse);
        expect(json['currentTimetableId'], 'tt-1');
      },
    );

    group('恢复备份', () {
      final storage = TempStorage();
      setUp(() => storage.setUp('phase_c_restore'));
      tearDown(storage.tearDown);

      test('恢复一份旧备份不重置更新节流（检查时间保留本机的）', () async {
        final state = AppState();
        await state.load();
        final t = DateTime(2026, 9, 23, 7);
        await state.setLastUpdateCheck(t);
        final snap = Storage.importJson(
          File('test/fixtures/v1_2_0/backup_v1.json').readAsStringSync(),
        );
        await state.restoreFrom(snap);
        expect(state.settings.lastUpdateCheck, t);
        expect(
          state.settings.toJson().containsKey('privacyAcceptedVersion'),
          isFalse,
        );
      });
    });
  });

  // ------------------------------------------------------------ 隐私说明正文

  group('隐私说明', () {
    test('assets/privacy.md 已登记为 asset，写到三种联网场景（教务 / 版本 / 假期表）和更新日期', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/privacy.md'));
      final md = File(PrivacyPolicy.assetPath).readAsStringSync();
      for (final must in <String>['教务', '版本', '假期表', PrivacyPolicy.updatedAt]) {
        expect(md, contains(must), reason: '缺少：$must');
      }
    });

    test('v1.5.0 白话正文（PLAN-1.5 第 3 节）：关键句都在，末行是更新日期，没有技术术语', () {
      final md = File(PrivacyPolicy.assetPath).readAsStringSync();
      expect(PrivacyPolicy.updatedAt, '2026-10-08');
      expect(md, isNot(contains('\r')), reason: 'LF 换行');
      expect(md.endsWith('\n') && !md.endsWith('\n\n'), isTrue);
      final lines = md.trimRight().split('\n');
      expect(lines.first, '# 隐私说明');
      expect(lines.last, '更新日期：${PrivacyPolicy.updatedAt}');
      for (final must in <String>[
        '没有账号、没有服务器、没有广告，也不做任何数据统计。',
        '**你的课表只存在手机里。**',
        '「设置 → 备份与恢复」',
        '**从教务导入时，账号密码直接给学校。**',
        '「记住教务登录」',
        '**App 只在三种情况联网：**',
        '1. 从教务导入时，打开学校的教务网站；',
        '2. 检查有没有新版本（每天最多一次）；',
        '3. 更新假期表（和检查版本用同一个地址）。',
        '不会带上你的任何信息',
        '**上课提醒在手机本地生成**',
        '只有「通知」（发上课提醒）和「闹钟和提醒」（让提醒准点）',
        '「设置 → 反馈」',
      ]) {
        expect(md, contains(must), reason: '缺少：$must');
      }
      for (final bad in <String>[
        'SDK',
        'JSON',
        'WebView',
        'Cookie',
        'jsDelivr',
        'raw.githubusercontent',
        'SHA',
        'API',
        'android.permission',
        '同意',
      ]) {
        expect(md, isNot(contains(bad)), reason: '还有术语「$bad」');
      }
    });

    test('简易 Markdown：标题 / 列表 / 有序列表 / 续行 / 引用 / 分隔线', () {
      final blocks = parseSimpleMarkdown(
        '# 标题\n\n段落第一行\n接着一行\n\n- 列表 A\n  - 子项\n1. 第一\n2. 第二\n   续行\n> 引用\n---\n### 小标题',
      );
      expect(blocks.map((b) => b.kind).toList(), <MdKind>[
        MdKind.h1,
        MdKind.paragraph,
        MdKind.bullet,
        MdKind.bullet,
        MdKind.numbered,
        MdKind.numbered,
        MdKind.quote,
        MdKind.rule,
        MdKind.h3,
      ]);
      expect(blocks[1].text, '段落第一行接着一行');
      expect(blocks[3].level, 1);
      expect(blocks[5].marker, '2.');
      expect(blocks[5].text, '第二续行');
      expect(
        parseSimpleMarkdown('- use\n  English words').single.text,
        'use English words',
      );
    });

    test('行内：**粗体** 与 `代码`，没闭合的按原文', () {
      final spans = parseInlineMarkdown('a**b**c`d`e**f');
      expect(spans.map((s) => s.text).toList(), <String>[
        'a',
        'b',
        'c',
        'd',
        'e**f',
      ]);
      expect(spans[1].bold, isTrue);
      expect(spans[3].code, isTrue);
    });

    testWidgets('隐私说明页能打开，渲染出三种联网场景的关键词', (tester) async {
      final (state, controller) = await loadState(tester);
      await pumpApp(tester, state, controller, const PrivacyPage());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      for (final word in <String>['教务', '版本', '假期表']) {
        expect(find.textContaining(word), findsWidgets, reason: '页面缺少：$word');
      }
      // AppBar 和正文 h1 各一处。
      expect(find.text('隐私说明'), findsNWidgets(2));
      expect(find.textContaining('你的课表只存在手机里。'), findsOneWidget);
      expect(find.textContaining('更新日期：2026-10-08'), findsOneWidget);
    });

    test('白话正文的解析：一个标题、三条有序列表、粗体开头的段落', () {
      final blocks = parseSimpleMarkdown(
        File(PrivacyPolicy.assetPath).readAsStringSync(),
      );
      expect(blocks.where((b) => b.kind == MdKind.h1).single.text, '隐私说明');
      final numbered = blocks.where((b) => b.kind == MdKind.numbered).toList();
      expect(numbered.map((b) => b.marker).toList(), <String>[
        '1.',
        '2.',
        '3.',
      ]);
      expect(numbered.first.text, '从教务导入时，打开学校的教务网站；');
      expect(
        blocks.where((b) => b.kind == MdKind.bullet || b.kind == MdKind.h2),
        isEmpty,
      );
      final mine = blocks.firstWhere((b) => b.text.contains('只存在手机里'));
      expect(mine.kind, MdKind.paragraph);
      final spans = parseInlineMarkdown(mine.text);
      expect(spans.first.text, '你的课表只存在手机里。');
      expect(spans.first.bold, isTrue);
      expect(spans.skip(1).every((s) => !s.bold), isTrue);
      expect(blocks.last.text, '更新日期：${PrivacyPolicy.updatedAt}');
    });
  });

  // ------------------------------------------------------------ 启动流程

  group('启动流程', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('phase_c_privacy'));
    tearDown(storage.tearDown);

    DateTime clock() => DateTime(2026, 10, 8, 9);

    /// 一个「已配置」的假更新源，记录被请求了几次。
    ({UpdateChecker checker, List<Uri> calls}) fakeChecker({int remote = 7}) {
      final calls = <Uri>[];
      final checker = UpdateChecker(
        sources: const <String>['https://updates.example/latest.json'],
        fetch: (uri, _) async {
          calls.add(uri);
          return jsonEncode(<String, dynamic>{
            'versionCode': remote,
            'versionName': '9.9.9',
          });
        },
        currentVersionCode: () async => 7,
      );
      return (checker: checker, calls: calls);
    }

    testWidgets('今天已经查过：不再查', (tester) async {
      final (state, controller) = await loadState(
        tester,
        seed: (s) => s.setLastUpdateCheck(DateTime(2026, 10, 8, 7)),
      );
      final fake = fakeChecker();
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(updateChecker: fake.checker, clock: clock),
      );
      await tester.pumpAndSettle();
      await settleWithRealIo(tester, rounds: 5);
      expect(fake.calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('首次启动：不弹隐私同意框，直接自动查一次；有新版弹更新对话框', (tester) async {
      final (state, controller) = await loadState(tester);
      expect(state.settings.lastUpdateCheck, isNull);
      final fake = fakeChecker(remote: 8);
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(updateChecker: fake.checker, clock: clock),
      );
      await tester.pump();
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();
      expect(find.text('同意'), findsNothing);
      expect(find.text('不同意并退出'), findsNothing);
      expect(fake.calls.length, 1);
      expect(state.settings.lastUpdateCheck, clock());
      expect(find.text('发现新版本 v9.9.9'), findsOneWidget);
      expect(find.text('去下载'), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v9.9.9'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // ------------------------------------------------------------ 设置页入口

  group('设置页「其他」组', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('phase_c_settings'));
    tearDown(storage.tearDown);

    testWidgets('未配置更新源：不显示「检查更新」；隐私说明 / 反馈入口在，从文件导入课表已删', (tester) async {
      final (state, controller) = await loadState(tester);
      await pumpApp(tester, state, controller, const SettingsPage());
      expect(
        find.byKey(const ValueKey<String>('settings-check-update')),
        findsNothing,
      );
      expect(find.text('检查更新'), findsNothing);
      expect(find.text('未配置更新源'), findsNothing);
      expect(find.text('关于${AppBrand.name}'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('settings-privacy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('settings-feedback')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('settings-import-timetable')),
        findsNothing,
      );
      expect(find.text('从文件导入课表'), findsNothing);
    });

    testWidgets('已配置更新源：可点，手动检查后提示「已是最新版本」；失败时提示白话「没能检查更新，稍后再试」', (
      tester,
    ) async {
      final (state, controller) = await loadState(tester);
      var shouldFail = false;
      final checker = UpdateChecker(
        sources: const <String>['https://updates.example/latest.json'],
        fetch: (_, _) async {
          if (shouldFail) throw Exception('DNS_FAIL');
          return '{"versionCode":7,"versionName":"1.3.0"}';
        },
        currentVersionCode: () async => 7,
      );
      await pumpApp(
        tester,
        state,
        controller,
        SettingsPage(updateChecker: checker),
      );
      final tile = find.byKey(const ValueKey<String>('settings-check-update'));
      await tester.ensureVisible(tile);
      expect(tester.widget<ListTile>(tile).enabled, isTrue);
      await tester.tap(tile);
      await tester.pump();
      await settleUntil(tester, find.text('已是最新版本'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('已是最新版本'), findsOneWidget);
      expect(state.settings.lastUpdateCheck, isNotNull);

      shouldFail = true;
      ScaffoldMessenger.of(tester.element(find.byType(SettingsPage)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pump();
      await settleUntil(tester, find.text('没能检查更新，稍后再试'));
      expect(find.text('没能检查更新，稍后再试'), findsOneWidget);
      expect(find.textContaining('DNS_FAIL'), findsNothing);
    });
  });

  group('反馈', () {
    test('DeviceDiagnostics.format：App 版本、Android 版本、机型', () {
      final text = DeviceDiagnostics.format(
        appVersion: '1.3.0',
        buildNumber: '7',
        device: <String, Object?>{
          'release': '15',
          'sdkInt': 35,
          'manufacturer': 'vivo',
          'brand': 'iQOO',
          'model': 'V2338A',
        },
      );
      expect(text, '简课表 v1.3.0（7）\nAndroid 15（API 35）\n机型：vivo / iQOO V2338A');
      expect(
        DeviceDiagnostics.format(appVersion: '1.3.0'),
        '简课表 v1.3.0\nAndroid 未知\n机型：未知 未知',
      );
    });

    test('NativeBridge.deviceInfo：原生给 Map 就透传，没有原生返回空 Map', () async {
      const channel = MethodChannel('test/phase_c_device');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final bridge = NativeBridge(channel: channel);
      expect(await bridge.deviceInfo(), isEmpty);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getDeviceInfo') {
          return <String, Object?>{
            'release': '14',
            'sdkInt': 34,
            'model': 'Pixel',
          };
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final info = await bridge.deviceInfo();
      expect(info['release'], '14');
      expect(info['sdkInt'], 34);
      expect(info['model'], 'Pixel');
    });

    testWidgets('未配置反馈渠道：只显示提示和「复制诊断信息」，复制到剪贴板', (tester) async {
      final storage = TempStorage();
      await tester.runAsync(() => storage.setUp('phase_c_feedback'));
      addTearDown(() => tester.runAsync(storage.tearDown));
      String? clip;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final (state, controller) = await loadState(tester);
      await pumpApp(
        tester,
        state,
        controller,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showFeedbackDialog(
                  context,
                  configured: false,
                  email: '',
                  diagnostics: () async => '简课表 v1.3.0\nAndroid 15\n机型：x y',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('把问题和截图发给把简课表发给你的人就行；可以先点「复制诊断信息」一起发。'), findsOneWidget);
      expect(find.textContaining('开发中的版本'), findsNothing);
      expect(find.textContaining('导入记录'), findsOneWidget);
      expect(find.textContaining('诊断样本'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('feedback-open-issues')),
        findsNothing,
      );
      expect(find.text('复制邮箱'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey<String>('feedback-copy-diagnostics')),
      );
      await tester.pumpAndSettle();
      expect(clip, '简课表 v1.3.0\nAndroid 15\n机型：x y');
      expect(find.text('诊断信息已复制'), findsOneWidget);
    });

    testWidgets('已配置：「去 GitHub 反馈」交给外部浏览器，文案说「系统版本」', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showFeedbackDialog(
                  context,
                  configured: true,
                  email: 'dev@example.com',
                  launcher: (uri) async {
                    opened.add(uri);
                    return true;
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('复制邮箱'), findsOneWidget);
      // v1.5.0 任务 E + R1-12：说「GitHub」和「系统版本」，不出现「Issues」「Android 版本」。
      expect(find.textContaining('欢迎到 GitHub 里留言'), findsOneWidget);
      expect(find.textContaining('系统版本'), findsOneWidget);
      expect(find.textContaining('Android 版本'), findsNothing);
      expect(find.textContaining('Issues'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey<String>('feedback-open-issues')),
      );
      await tester.pumpAndSettle();
      expect(opened.single.path, endsWith('/issues'));
    });
  });
}
