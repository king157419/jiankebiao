import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/repo_config.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/core/update/update_config.dart';
import 'package:shu_schedule/core/update/update_dialog.dart';

/// v1.3.0 Phase C.5：检查更新（解析、版本比较、多源回退、超时、节流）。
void main() {
  const sha =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  String latest({Object? code = 8, Object? name = '1.3.1'}) =>
      jsonEncode(<String, dynamic>{
        'versionCode': code,
        'versionName': name,
        'changelog': '修复了小组件\n新增调休',
        'downloadUrls': <String>[
          'ftp://bad.example.com/a.apk',
          'https://github.com/o/r/releases/download/v1.3.1/a.apk',
          'not a url',
          'https://mirror.example.com/a.apk',
        ],
        'sha256': sha.toUpperCase(),
      });

  group('UpdateInfo.fromJson', () {
    test('解析字段；只留 http(s) 下载地址；sha256 转小写', () {
      final info = UpdateInfo.fromJson(jsonDecode(latest()));
      expect(info.versionCode, 8);
      expect(info.versionName, '1.3.1');
      expect(info.changelog, '修复了小组件\n新增调休');
      expect(info.downloadUrls, <String>[
        'https://github.com/o/r/releases/download/v1.3.1/a.apk',
        'https://mirror.example.com/a.apk',
      ]);
      expect(info.firstDownloadUrl, info.downloadUrls.first);
      expect(info.sha256, sha);
    });

    test('v1.4.0：holidays.sha256 可选，解析成小写；缺失 / 不合法为 null', () {
      final info = UpdateInfo.fromJson(<String, dynamic>{
        'versionCode': 9,
        'versionName': '1.4.0',
        'holidays': <String, dynamic>{
          'sha256': sha.toUpperCase(),
          'updatedAt': '2026-10-06',
        },
      });
      expect(info.holidaysSha256, sha);
      expect(info.sha256, isNull);
      expect(
        UpdateInfo.fromJson(<String, dynamic>{
          'versionCode': 9,
          'versionName': '1.4.0',
          'holidays': <String, dynamic>{'sha256': 'abc'},
        }).holidaysSha256,
        isNull,
      );
      expect(
        UpdateInfo.fromJson(<String, dynamic>{
          'versionCode': 9,
          'versionName': '1.4.0',
          'holidays': 'oops',
        }).holidaysSha256,
        isNull,
      );
      expect(UpdateInfo.fromJson(jsonDecode(latest())).holidaysSha256, isNull);
    });

    test('versionCode 可以是字符串数字；changelog 可以是数组；坏 sha256 丢掉', () {
      final info = UpdateInfo.fromJson(<String, dynamic>{
        'versionCode': ' 9 ',
        'versionName': '1.4.0',
        'changelog': <dynamic>['一', 2, '二'],
        'sha256': 'xyz',
      });
      expect(info.versionCode, 9);
      expect(info.changelog, '· 一\n· 二');
      expect(info.downloadUrls, isEmpty);
      expect(info.firstDownloadUrl, isNull);
      expect(info.sha256, isNull);
    });

    test('缺 versionCode / versionName 或顶层不是对象：FormatException', () {
      expect(() => UpdateInfo.fromJson(<dynamic>[]), throwsFormatException);
      expect(
        () => UpdateInfo.fromJson(<String, dynamic>{'versionName': 'x'}),
        throwsFormatException,
      );
      expect(
        () => UpdateInfo.fromJson(<String, dynamic>{
          'versionCode': 0,
          'versionName': 'x',
        }),
        throwsFormatException,
      );
      expect(
        () => UpdateInfo.fromJson(<String, dynamic>{'versionCode': 3}),
        throwsFormatException,
      );
    });
  });

  group('版本比较', () {
    test('isNewer：远端大才算新；本机读不到（0）不提示', () {
      expect(UpdateChecker.isNewer(8, 7), isTrue);
      expect(UpdateChecker.isNewer(7, 7), isFalse);
      expect(UpdateChecker.isNewer(6, 7), isFalse);
      expect(UpdateChecker.isNewer(8, 0), isFalse);
    });
  });

  group('配置', () {
    test('源从 kRepo 派生；kRepo 还是 OWNER/REPO 占位符 → 未配置（不配 Gitee 时 2 个源）', () {
      expect(kRepo.isPlaceholder, isTrue);
      expect(UpdateConfig.isConfigured, isFalse);
      expect(UpdateChecker().isConfigured, isFalse);
      expect(UpdateConfig.sources, <String>[
        for (final u in kRepo.rawUrls('latest.json')) u.toString(),
      ]);
      expect(UpdateConfig.sources.length, 2);
      expect(UpdateConfig.sources.first, contains('cdn.jsdelivr.net/gh/'));
      expect(UpdateConfig.sources.last, contains('raw.githubusercontent.com'));
      expect(
        UpdateConfig.sources.every((s) => s.endsWith('/latest.json')),
        isTrue,
      );
      expect(UpdateConfig.placeholder, 'OWNER/REPO');
      expect(UpdateConfig.perSourceTimeout, const Duration(seconds: 5));
      expect(UpdateConfig.maxResponseBytes, 64 * 1024);
    });

    test('配置了真实仓库 + Gitee：latest.json 有 3 个源，Gitee 在最前', () {
      const repo = RepoConfig(
        githubOwner: 'someone',
        githubRepo: 'jiankebiao',
        giteeOwner: 'someone-cn',
        giteeRepo: 'jiankebiao',
      );
      final urls = <String>[
        for (final u in repo.rawUrls('latest.json')) u.toString(),
      ];
      expect(urls, <String>[
        'https://gitee.com/someone-cn/jiankebiao/raw/main/latest.json',
        'https://cdn.jsdelivr.net/gh/someone/jiankebiao@main/latest.json',
        'https://raw.githubusercontent.com/someone/jiankebiao/main/latest.json',
      ]);
      expect(UpdateConfig.sourcesConfigured(urls), isTrue);
      expect(UpdateChecker(sources: urls).isConfigured, isTrue);
    });

    test('sourcesConfigured：任何一个带占位符都算没配好；空列表也不算', () {
      expect(
        UpdateConfig.sourcesConfigured(<String>['https://a/latest.json']),
        isTrue,
      );
      expect(
        UpdateConfig.sourcesConfigured(<String>[
          'https://a/latest.json',
          'https://cdn.jsdelivr.net/gh/OWNER/REPO@main/latest.json',
        ]),
        isFalse,
      );
      expect(UpdateConfig.sourcesConfigured(<String>[]), isFalse);
    });
  });

  group('UpdateChecker.check', () {
    test('未配置：直接返回 notConfigured，不调用 fetch', () async {
      var calls = 0;
      final checker = UpdateChecker(
        fetch: (_, _) async {
          calls++;
          return latest();
        },
        currentVersionCode: () async => 7,
      );
      final r = await checker.check();
      expect(r.status, UpdateStatus.notConfigured);
      expect(calls, 0);
    });

    test('有新版：available，带回 info 与源', () async {
      final checker = UpdateChecker(
        sources: const <String>['https://a.example/latest.json'],
        fetch: (_, _) async => latest(code: 8),
        currentVersionCode: () async => 7,
      );
      final r = await checker.check();
      expect(r.status, UpdateStatus.available);
      expect(r.hasUpdate, isTrue);
      expect(r.info!.versionName, '1.3.1');
      expect(r.currentVersionCode, 7);
      expect(r.source, 'https://a.example/latest.json');
    });

    test('远端不比本机新：upToDate', () async {
      final checker = UpdateChecker(
        sources: const <String>['https://a.example/latest.json'],
        fetch: (_, _) async => latest(code: 7),
        currentVersionCode: () async => 7,
      );
      expect((await checker.check()).status, UpdateStatus.upToDate);
    });

    test('第一个源失败（异常 / 坏 JSON）就依次试下一个，按顺序请求', () async {
      final requested = <String>[];
      final checker = UpdateChecker(
        sources: const <String>[
          'https://raw.example/latest.json',
          'https://bad-json.example/latest.json',
          'https://cdn.example/latest.json',
        ],
        fetch: (uri, _) async {
          requested.add(uri.host);
          if (uri.host == 'raw.example') throw Exception('连接被重置');
          if (uri.host == 'bad-json.example') return '<html>';
          return latest(code: 9);
        },
        currentVersionCode: () async => 7,
      );
      final r = await checker.check();
      expect(requested, <String>[
        'raw.example',
        'bad-json.example',
        'cdn.example',
      ]);
      expect(r.status, UpdateStatus.available);
      expect(r.source, 'https://cdn.example/latest.json');
      expect(r.errors.length, 2);
    });

    test('每个源单独超时：卡住的源不会拖住后面的源', () async {
      final started = <String>[];
      final checker = UpdateChecker(
        sources: const <String>[
          'https://hang.example/latest.json',
          'https://ok.example/latest.json',
        ],
        timeout: const Duration(milliseconds: 50),
        fetch: (uri, _) {
          started.add(uri.host);
          if (uri.host == 'hang.example') return Completer<String>().future;
          return Future<String>.value(latest(code: 8));
        },
        currentVersionCode: () async => 7,
      );
      final r = await checker.check();
      expect(started, <String>['hang.example', 'ok.example']);
      expect(r.status, UpdateStatus.available);
      expect(r.errors.single, contains('超时'));
    });

    test('全部失败：failed，列出每个源的原因，不抛异常', () async {
      final checker = UpdateChecker(
        sources: const <String>['https://a.example/x', 'https://b.example/x'],
        fetch: (_, _) async => throw Exception('断网'),
        currentVersionCode: () async => 7,
      );
      final r = await checker.check();
      expect(r.status, UpdateStatus.failed);
      expect(r.errors.length, 2);
    });

    test('默认网络实现只允许 https（带 maxBytes 参数的调用也一样）', () async {
      expect(
        () => UpdateChecker.httpFetch(
          Uri.parse('http://a.example/x'),
          const Duration(seconds: 1),
        ),
        throwsA(anything),
      );
      expect(
        () => UpdateChecker.httpFetch(
          Uri.parse('http://a.example/x'),
          const Duration(seconds: 1),
          maxBytes: 256 * 1024,
        ),
        throwsA(anything),
      );
      // 带可选参数的实现仍然能当作 UpdateFetch 注入。
      const UpdateFetch f = UpdateChecker.httpFetch;
      expect(f, isNotNull);
    });
  });

  group('自动检查节流 shouldAutoCheck', () {
    final now = DateTime(2026, 9, 23, 9);
    test('没配置：不查', () {
      expect(
        UpdateChecker.shouldAutoCheck(
          configured: false,
          lastCheck: null,
          now: now,
        ),
        isFalse,
      );
    });
    test('从没查过：查；今天查过：不查；昨天查过（哪怕不到 24 小时）：查；时间在未来：查', () {
      bool go(DateTime? last) => UpdateChecker.shouldAutoCheck(
        configured: true,
        lastCheck: last,
        now: now,
      );
      expect(go(null), isTrue);
      expect(go(DateTime(2026, 9, 23, 0, 1)), isFalse);
      expect(go(DateTime(2026, 9, 22, 23, 59)), isTrue);
      expect(go(DateTime(2025, 9, 23, 9)), isTrue);
      expect(go(DateTime(2026, 9, 24)), isTrue);
    });
  });

  group('去下载', () {
    test('openFirstDownload：依次尝试，第一个能打开的为准', () async {
      final tried = <String>[];
      final info = UpdateInfo.fromJson(jsonDecode(latest()));
      final ok = await openFirstDownload(info, (uri) async {
        tried.add(uri.host);
        return uri.host == 'mirror.example.com';
      });
      expect(ok, isTrue);
      expect(tried, <String>['github.com', 'mirror.example.com']);
      expect(
        await openFirstDownload(
          const UpdateInfo(versionCode: 1, versionName: 'x'),
          (_) async => true,
        ),
        isFalse,
      );
    });

    testWidgets('「发现新版本」对话框：版本号、更新日志、下载说明；不显示校验值（v1.5.0 任务 E）', (tester) async {
      final info = UpdateInfo.fromJson(jsonDecode(latest()));
      expect(info.sha256, sha, reason: '照旧解析，只是不给用户看');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showUpdateDialog(
                  context,
                  info,
                  launcher: (_) async => true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.3.1'), findsOneWidget);
      expect(find.text('修复了小组件\n新增调休'), findsOneWidget);
      expect(find.textContaining('点「去下载」会用系统浏览器打开下载页'), findsOneWidget);
      expect(find.textContaining('SHA'), findsNothing);
      expect(find.textContaining(sha), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
    });
  });
}
