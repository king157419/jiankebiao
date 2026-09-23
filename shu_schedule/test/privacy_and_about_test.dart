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

/// v1.3.0 Phase C.1 / C.5 / C.6：品牌、隐私说明与首启确认、检查更新入口、反馈。
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
    test('1.2.0 的 settings.json（没有新字段）→ 没同意过隐私说明、没检查过更新', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'currentTimetableId': 'a',
        'themeId': 'mint',
        'showTimeInGrid': true,
        'settingsVersion': 2,
      });
      expect(s.privacyAcceptedVersion, 0);
      expect(s.lastUpdateCheck, isNull);
      expect(s.showTimeInGrid, isTrue);
    });

    test('JSON 往返；脏数据容错', () {
      final s = AppSettings(
        privacyAcceptedVersion: 1,
        lastUpdateCheck: DateTime(2026, 9, 23, 8, 30),
      );
      final back = AppSettings.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.privacyAcceptedVersion, 1);
      expect(back.lastUpdateCheck, DateTime(2026, 9, 23, 8, 30));
      final dirty = AppSettings.fromJson(<String, dynamic>{
        'privacyAcceptedVersion': 'yes',
        'lastUpdateCheck': 'not a date',
      });
      expect(dirty.privacyAcceptedVersion, 0);
      expect(dirty.lastUpdateCheck, isNull);
    });

    group('恢复备份', () {
      final storage = TempStorage();
      setUp(() => storage.setUp('phase_c_restore'));
      tearDown(storage.tearDown);

      test('恢复一份旧备份不会让用户再同意一次隐私说明，也不重置更新节流', () async {
        final state = AppState();
        await state.load();
        await state.acceptPrivacy(1);
        final t = DateTime(2026, 9, 23, 7);
        await state.setLastUpdateCheck(t);
        final snap = Storage.importJson(
          File('test/fixtures/v1_2_0/backup_v1.json').readAsStringSync(),
        );
        expect(snap.settings.privacyAcceptedVersion, 0);
        await state.restoreFrom(snap);
        expect(state.settings.privacyAcceptedVersion, 1);
        expect(state.settings.lastUpdateCheck, t);
      });
    });
  });

  // ------------------------------------------------------------ 隐私说明正文

  group('隐私说明', () {
    test('assets/privacy.md 已登记为 asset，包含 REVIEW-2 §7.6 要求的各条', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/privacy.md'));
      final md = File(PrivacyPolicy.assetPath).readAsStringSync();
      for (final must in <String>[
        '开发者与联系方式',
        '我们收集了什么',
        '权限清单',
        '第三方组件清单',
        '存储位置、保存期限与删除',
        '未成年人',
        '本说明的更新',
        'android.permission.INTERNET',
        'IP 地址',
        '卸载即全部删除',
        PrivacyPolicy.updatedAt,
      ]) {
        expect(md, contains(must), reason: '缺少：$must');
      }
      // 第三方组件清单覆盖 pubspec 里的全部运行时依赖。
      final deps = RegExp(
        r'^dependencies:\n((?:  .*\n|\n)*?)dev_dependencies:',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1)!;
      final names = RegExp(r'^  ([a-z_]+):', multiLine: true)
          .allMatches(deps)
          .map((m) => m.group(1)!)
          .where((n) => n != 'flutter')
          .toList();
      expect(names, contains('package_info_plus'));
      for (final n in names) {
        expect(md, contains('`$n`'), reason: '第三方组件清单缺少 $n');
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

    testWidgets('隐私说明页能把 privacy.md 渲染出来', (tester) async {
      final (state, controller) = await loadState(tester);
      await pumpApp(tester, state, controller, const PrivacyPage());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('简课表隐私说明'), findsOneWidget);
      expect(find.text('三、权限清单'), findsOneWidget);
      expect(find.text('四、第三方组件清单'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ 首启确认

  group('首次启动的隐私确认', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('phase_c_privacy'));
    tearDown(storage.tearDown);

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

    NativeBridge silentBridge() =>
        NativeBridge(channel: const MethodChannel('test/phase_c_native'));

    testWidgets('同意之前不触发更新检查；同意后记录版本并检查一次', (tester) async {
      final (state, controller) = await loadState(tester);
      final fake = fakeChecker();
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(bridge: silentBridge(), updateChecker: fake.checker),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('privacy-consent')),
        findsOneWidget,
      );
      // 等一会儿，确认同意前真的没有请求。
      await settleWithRealIo(tester, rounds: 5);
      expect(fake.calls, isEmpty);
      expect(state.settings.privacyAcceptedVersion, 0);
      expect(state.settings.lastUpdateCheck, isNull);

      await tester.tap(find.byKey(const ValueKey<String>('privacy-accept')));
      await tester.pump();
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('privacy-consent')),
        findsNothing,
      );
      expect(state.settings.privacyAcceptedVersion, PrivacyPolicy.version);
      expect(fake.calls.length, 1);
      expect(state.settings.lastUpdateCheck, isNotNull);
    });

    testWidgets('不同意：不记录、不检查更新，交给退出回调', (tester) async {
      final (state, controller) = await loadState(tester);
      final fake = fakeChecker();
      var declined = 0;
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(
          bridge: silentBridge(),
          updateChecker: fake.checker,
          onPrivacyDeclined: () => declined++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('privacy-decline')));
      await tester.pump();
      await settleWithRealIo(tester, rounds: 5);
      expect(declined, 1);
      expect(fake.calls, isEmpty);
      expect(state.settings.privacyAcceptedVersion, 0);
    });

    testWidgets('已同意过、今天已经查过：不弹框，也不再查', (tester) async {
      final (state, controller) = await loadState(
        tester,
        seed: (s) async {
          await s.acceptPrivacy(PrivacyPolicy.version);
          await s.setLastUpdateCheck(DateTime.now());
        },
      );
      final fake = fakeChecker();
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(bridge: silentBridge(), updateChecker: fake.checker),
      );
      await tester.pumpAndSettle();
      await settleWithRealIo(tester, rounds: 5);
      expect(
        find.byKey(const ValueKey<String>('privacy-consent')),
        findsNothing,
      );
      expect(fake.calls, isEmpty);
    });

    testWidgets('已同意过、今天没查过：自动查一次，有新版弹更新对话框', (tester) async {
      final (state, controller) = await loadState(
        tester,
        seed: (s) => s.acceptPrivacy(PrivacyPolicy.version),
      );
      final fake = fakeChecker(remote: 8);
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(bridge: silentBridge(), updateChecker: fake.checker),
      );
      await tester.pump();
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();
      expect(fake.calls.length, 1);
      expect(find.text('发现新版本 v9.9.9'), findsOneWidget);
      expect(find.text('去下载'), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v9.9.9'), findsNothing);
    });

    testWidgets('快捷方式动作在同意前挂起，同意后才处理', (tester) async {
      final (state, controller) = await loadState(tester);
      const channel = MethodChannel('test/phase_c_native_action');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getLaunchAction') return 'today';
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(
          bridge: NativeBridge(channel: channel),
          updateChecker: fakeChecker().checker,
        ),
      );
      await tester.pumpAndSettle();
      NavigationBar bar() =>
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar().selectedIndex, 0);
      await tester.tap(find.byKey(const ValueKey<String>('privacy-accept')));
      await tester.pump();
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();
      expect(bar().selectedIndex, 1); // 「今日」
    });
  });

  // ------------------------------------------------------------ 设置页入口

  group('设置页「关于」组', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('phase_c_settings'));
    tearDown(storage.tearDown);

    testWidgets('未配置更新源：「检查更新」显示「未配置更新源」且禁用；隐私说明 / 反馈入口在', (tester) async {
      final (state, controller) = await loadState(tester);
      await pumpApp(tester, state, controller, const SettingsPage());
      final tile = find.byKey(const ValueKey<String>('settings-check-update'));
      await tester.ensureVisible(tile);
      expect(tester.widget<ListTile>(tile).enabled, isFalse);
      expect(find.text('未配置更新源'), findsOneWidget);
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
        findsOneWidget,
      );
    });

    testWidgets('已配置更新源：可点，手动检查后提示「已是最新版本」', (tester) async {
      final (state, controller) = await loadState(tester);
      final checker = UpdateChecker(
        sources: const <String>['https://updates.example/latest.json'],
        fetch: (_, _) async => '{"versionCode":7,"versionName":"1.3.0"}',
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
      await settleWithRealIo(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('已是最新版本'), findsOneWidget);
      expect(state.settings.lastUpdateCheck, isNotNull);
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
      expect(find.textContaining('反馈渠道还没有配置好'), findsOneWidget);
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

    testWidgets('已配置：「去 GitHub 反馈」交给外部浏览器', (tester) async {
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
      await tester.tap(
        find.byKey(const ValueKey<String>('feedback-open-issues')),
      );
      await tester.pumpAndSettle();
      expect(opened.single.path, endsWith('/issues'));
    });
  });
}
