import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/holiday_repository.dart';
import 'package:shu_schedule/core/repo_config.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/models/app_settings.dart';

import 'helpers/harness.dart';

/// v1.4.0 A2：假日表远程下发（HolidayRepository）。
void main() {
  final bundledText = File('assets/holidays.json').readAsStringSync();
  final bundled = HolidayPresets.fromJson(jsonDecode(bundledText) as Map);

  const configured = RepoConfig(githubOwner: 'me', githubRepo: 'jkb');
  const withGitee = RepoConfig(
    githubOwner: 'me',
    githubRepo: 'jkb',
    giteeOwner: 'me-cn',
    giteeRepo: 'jkb',
  );

  /// 一份「远程」假日表：只有 2027 年国家安排，没有学校——用来证明是整体替换、不合并。
  String remoteJson({Object? version = 1, Object? updatedAt = '2026-11-02'}) =>
      jsonEncode(<String, dynamic>{
        'version': ?version,
        'updatedAt': ?updatedAt,
        'national': <String, dynamic>{
          '2027': <String, dynamic>{
            'source': '国务院办公厅关于2027年部分节假日安排的通知',
            'holidays': <dynamic>[
              <String, dynamic>{
                'name': '元旦',
                'off': <String>['2027-01-01'],
                'work': <String>[],
              },
            ],
          },
        },
        'schools': <String, dynamic>{},
      });

  String shaOf(String text) =>
      crypto.sha256.convert(utf8.encode(text)).toString();

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('holiday_repository_test');
  });
  tearDown(() async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows 偶尔还有没关的句柄。
    }
  });

  File cacheFile() => File(
    '${dir.path}${Platform.pathSeparator}${HolidayRepository.cacheFileName}',
  );

  HolidayRepository repoWith({
    RepoConfig repo = configured,
    UpdateFetch? fetch,
    int maxBytes = HolidayRepository.defaultMaxBytes,
    Duration timeout = const Duration(seconds: 5),
  }) => HolidayRepository(
    repo: repo,
    fetch: fetch ?? (_, _) async => throw Exception('不该联网'),
    dirProvider: () => dir,
    loadBundled: () async => bundled,
    maxBytes: maxBytes,
    timeout: timeout,
  );

  /// 没有 holidays.sha256 的 latest.json（只依赖 TLS）。
  const noSha = UpdateInfo(versionCode: 9, versionName: '1.4.0');

  group('内置数据', () {
    test('holidays.json 顶层 version = 1、updatedAt = 2026-10-06，来源是内置', () {
      expect(bundled.version, 1);
      expect(bundled.isValid, isTrue);
      expect(bundled.updatedAt, DateTime(2026, 10, 6));
      expect(bundled.updatedAtText, '2026-10-06');
      expect(bundled.source, HolidayDataSource.bundled);
      expect(
        HolidayPresets.tryParseStrict(jsonDecode(bundledText))?.updatedAt,
        DateTime(2026, 10, 6),
      );
    });

    test('version 不是 1 → 无效、不读条目；严格解析要求 version 与 updatedAt', () {
      final v2 = HolidayPresets.fromJson(
        jsonDecode(remoteJson(version: 2)) as Map,
      );
      expect(v2.isValid, isFalse);
      expect(v2.national, isEmpty);
      expect(
        HolidayPresets.tryParseStrict(jsonDecode(remoteJson(version: 2))),
        isNull,
      );
      expect(
        HolidayPresets.tryParseStrict(jsonDecode(remoteJson(version: 'x'))),
        isNull,
      );
      expect(
        HolidayPresets.tryParseStrict(jsonDecode(remoteJson(version: null))),
        isNull,
      );
      expect(
        HolidayPresets.tryParseStrict(jsonDecode(remoteJson(updatedAt: null))),
        isNull,
      );
      expect(
        HolidayPresets.tryParseStrict(
          jsonDecode(remoteJson(updatedAt: 'yesterday')),
        ),
        isNull,
      );
      expect(HolidayPresets.tryParseStrict(<dynamic>[]), isNull);
      final ok = HolidayPresets.tryParseStrict(jsonDecode(remoteJson()))!;
      expect(ok.source, HolidayDataSource.remote);
      expect(ok.national.keys, <int>[2027]);
    });
  });

  group('load', () {
    test('没有缓存 → 内置', () async {
      final p = await repoWith().load();
      expect(p.source, HolidayDataSource.bundled);
      expect(p.updatedAt, DateTime(2026, 10, 6));
    });

    test('缓存比内置新 → 整体换成缓存（不合并内置的学校数据）', () async {
      await cacheFile().writeAsString(remoteJson(updatedAt: '2026-11-02'));
      final p = await repoWith().load();
      expect(p.source, HolidayDataSource.remote);
      expect(p.updatedAt, DateTime(2026, 11, 2));
      expect(p.national.keys, <int>[2027]);
      expect(p.schools, isEmpty);
    });

    test('缓存不比内置新（更旧 / 同一天）→ 忽略缓存', () async {
      await cacheFile().writeAsString(remoteJson(updatedAt: '2026-09-01'));
      expect((await repoWith().load()).source, HolidayDataSource.bundled);
      await cacheFile().writeAsString(remoteJson(updatedAt: '2026-10-06'));
      expect((await repoWith().load()).source, HolidayDataSource.bundled);
    });

    test('损坏的缓存（坏 JSON / 版本不对 / 缺 updatedAt）→ 忽略，回退内置', () async {
      for (final bad in <String>[
        '{"version": 1, "updatedAt": "2027-01-01", ',
        '',
        '[]',
        remoteJson(version: 2, updatedAt: '2027-01-01'),
        remoteJson(updatedAt: null),
      ]) {
        await cacheFile().writeAsString(bad);
        final p = await repoWith().load();
        expect(p.source, HolidayDataSource.bundled, reason: bad);
        expect(p.schools.keys, contains('shu'), reason: bad);
      }
    });

    test('内置读取失败 → 空数据，不抛异常', () async {
      final repo = HolidayRepository(
        repo: configured,
        dirProvider: () => dir,
        loadBundled: () async => throw Exception('asset 坏了'),
      );
      final p = await repo.load();
      expect(p.national, isEmpty);
      expect(p.schools, isEmpty);
    });
  });

  group('refresh：不发请求的几种情况', () {
    test('仓库未配置 → notConfigured，不联网、不记时间', () async {
      var calls = 0;
      var attempts = 0;
      final r = await repoWith(
        repo: kRepo,
        fetch: (_, _) async {
          calls++;
          return remoteJson();
        },
      ).refresh(force: true, onSuccess: (_) => attempts++);
      expect(r.status, HolidayRefreshStatus.notConfigured);
      expect(calls, 0);
      expect(attempts, 0);
    });

    test('24 小时内刷新过 → throttled；force 不受限', () async {
      final now = DateTime(2026, 10, 7, 9);
      var calls = 0;
      final repo = repoWith(
        fetch: (uri, _) async {
          calls++;
          return remoteJson(updatedAt: '2026-10-06');
        },
      );
      final throttled = await repo.refresh(
        now: now,
        lastRefresh: DateTime(2026, 10, 6, 10),
        manifest: noSha,
      );
      expect(throttled.status, HolidayRefreshStatus.throttled);
      expect(calls, 0);
      final forced = await repo.refresh(
        force: true,
        now: now,
        lastRefresh: DateTime(2026, 10, 6, 10),
        manifest: noSha,
      );
      expect(forced.status, HolidayRefreshStatus.unchanged);
      expect(calls, 2, reason: '都不比当前新 → jsDelivr、GitHub raw 都试一遍');
    });

    test('shouldRefresh：没刷新过 / 满 24 小时 / 时间在未来 → 刷新', () {
      final now = DateTime(2026, 10, 7, 9);
      bool go(DateTime? last) =>
          HolidayRepository.shouldRefresh(lastRefresh: last, now: now);
      expect(go(null), isTrue);
      expect(go(DateTime(2026, 10, 7, 8, 59)), isFalse);
      expect(go(DateTime(2026, 10, 6, 9, 1)), isFalse);
      expect(go(DateTime(2026, 10, 6, 9)), isTrue);
      expect(go(DateTime(2026, 9, 1)), isTrue);
      expect(go(DateTime(2026, 10, 8)), isTrue);
    });
  });

  group('refresh：联网', () {
    test('更新于当前 → updated：原子写缓存，之后 load 用远程数据；成功后记下刷新时间', () async {
      final now = DateTime(2026, 11, 3, 8);
      final attempts = <DateTime>[];
      final requested = <Uri>[];
      final repo = repoWith(
        fetch: (uri, _) async {
          requested.add(uri);
          return remoteJson();
        },
      );
      final r = await repo.refresh(
        now: now,
        onSuccess: attempts.add,
        manifest: noSha,
      );
      expect(r.status, HolidayRefreshStatus.updated);
      expect(r.isUpdated, isTrue);
      expect(r.presets!.updatedAt, DateTime(2026, 11, 2));
      expect(r.presets!.source, HolidayDataSource.remote);
      expect(attempts, <DateTime>[now]);
      expect(requested.single.host, 'cdn.jsdelivr.net');
      expect(
        requested.single.path,
        '/gh/me/jkb@main/shu_schedule/assets/holidays.json',
      );
      expect(r.source, requested.single);
      expect(cacheFile().readAsStringSync(), remoteJson());
      final tmpLeft = dir
          .listSync()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(tmpLeft, isEmpty);
      final loaded = await repo.load();
      expect(loaded.source, HolidayDataSource.remote);
      expect(loaded.national.keys, <int>[2027]);
    });

    test('配了 Gitee：按 Gitee → jsDelivr → GitHub raw 依次尝试，第一个成功的为准', () async {
      final hosts = <String>[];
      final r = await repoWith(
        repo: withGitee,
        fetch: (uri, _) async {
          hosts.add(uri.host);
          if (uri.host == 'gitee.com') throw Exception('连接超时');
          return remoteJson();
        },
      ).refresh(force: true, manifest: noSha);
      expect(hosts, <String>['gitee.com', 'cdn.jsdelivr.net']);
      expect(r.status, HolidayRefreshStatus.updated);
      expect(r.source!.host, 'cdn.jsdelivr.net');
      expect(r.errors.single, contains('gitee.com'));
    });

    test('远程和当前一样新 → unchanged，不写缓存；unchanged 也算成功、记时间', () async {
      final attempts = <DateTime>[];
      final now = DateTime(2026, 10, 7, 9);
      final hosts = <String>[];
      final r =
          await repoWith(
            fetch: (uri, _) async {
              hosts.add(uri.host);
              return remoteJson(updatedAt: '2026-10-06');
            },
          ).refresh(
            force: true,
            now: now,
            manifest: noSha,
            onSuccess: attempts.add,
          );
      expect(r.status, HolidayRefreshStatus.unchanged);
      expect(r.presets!.source, HolidayDataSource.bundled);
      expect(r.source!.host, 'cdn.jsdelivr.net', reason: '第一个读到合法数据的地址');
      expect(hosts, <String>[
        'cdn.jsdelivr.net',
        'raw.githubusercontent.com',
      ], reason: 'P3-5：不比当前新时接着试后面的地址');
      expect(cacheFile().existsSync(), isFalse);
      expect(attempts, <DateTime>[now]);
    });

    test('镜像滞后：Gitee 是旧的、jsDelivr 是新的 → updated（P3-5）', () async {
      final hosts = <String>[];
      final r = await repoWith(
        repo: withGitee,
        fetch: (uri, _) async {
          hosts.add(uri.host);
          return uri.host == 'gitee.com'
              ? remoteJson(updatedAt: '2026-10-06')
              : remoteJson(updatedAt: '2026-11-02');
        },
      ).refresh(force: true, manifest: noSha);
      expect(r.status, HolidayRefreshStatus.updated);
      expect(r.source!.host, 'cdn.jsdelivr.net');
      expect(r.presets!.updatedAt, DateTime(2026, 11, 2));
      expect(hosts, <String>['gitee.com', 'cdn.jsdelivr.net']);
      expect(
        cacheFile().readAsStringSync(),
        remoteJson(updatedAt: '2026-11-02'),
      );
    });

    test('镜像滞后 + 校验：传入的 manifest 来自旧镜像，新地址用它自己的 latest.json 核对', () async {
      final oldBody = remoteJson(updatedAt: '2026-10-06');
      final newBody = remoteJson(updatedAt: '2026-11-02');
      String latest(String body) => jsonEncode(<String, dynamic>{
        'versionCode': 9,
        'versionName': '1.4.0',
        'holidays': <String, dynamic>{'sha256': shaOf(body)},
      });
      final staleManifest = UpdateInfo.fromJson(jsonDecode(latest(oldBody)));
      final r = await repoWith(
        repo: withGitee,
        fetch: (uri, _) async {
          final stale = uri.host == 'gitee.com';
          if (uri.path.endsWith('latest.json')) {
            return latest(stale ? oldBody : newBody);
          }
          return stale ? oldBody : newBody;
        },
      ).refresh(force: true, manifest: staleManifest);
      expect(r.status, HolidayRefreshStatus.updated);
      expect(r.source!.host, 'cdn.jsdelivr.net');
    });

    test('失败不记刷新时间（fixlist ①）', () async {
      final attempts = <DateTime>[];
      final r = await repoWith(fetch: (_, _) async => throw Exception('断网'))
          .refresh(force: true, manifest: noSha, onSuccess: attempts.add);
      expect(r.status, HolidayRefreshStatus.failed);
      expect(attempts, isEmpty);
    });

    test('错误只带 host 和简短原因，不带完整 URL（P3-6）', () async {
      final r = await repoWith(
        fetch: (uri, _) async => throw HttpException('HTTP 404', uri: uri),
      ).refresh(force: true, manifest: noSha);
      expect(r.errors.first, 'cdn.jsdelivr.net：HTTP 404');
      expect(r.firstError, 'cdn.jsdelivr.net：HTTP 404');
      expect(r.errors.join(), isNot(contains('https://')));
      expect(
        HolidayRepository.shortError(const SocketException('x')),
        '连不上服务器',
      );
      expect(HolidayRepository.shortError(Exception('a' * 100)).length, 61);
    });

    test('整次刷新不超过 totalTimeout（P3-4）', () async {
      final repo = HolidayRepository(
        repo: withGitee,
        fetch: (_, _) => Completer<String>().future,
        dirProvider: () => dir,
        loadBundled: () async => bundled,
        timeout: const Duration(milliseconds: 400),
        totalTimeout: const Duration(milliseconds: 600),
      );
      final watch = Stopwatch()..start();
      final r = await repo.refresh(force: true);
      watch.stop();
      expect(r.status, HolidayRefreshStatus.failed);
      expect(r.errors, hasLength(3));
      expect(r.errors, everyElement(contains('超时')));
      expect(
        watch.elapsed,
        lessThan(const Duration(milliseconds: 1100)),
        reason: '3 × 400 ms 串行要 1.2 s，总超时把它截在 0.6 s 左右',
      );
      expect(
        HolidayRepository.defaultTotalTimeout,
        const Duration(seconds: 10),
      );
    });

    test('没传 manifest：同一地址的 latest.json 与 holidays.json 并发取（P3-4）', () async {
      final pending = <String, Completer<String>>{};
      final repo = repoWith(
        fetch: (uri, _) {
          final c = Completer<String>();
          pending['${uri.host}${uri.path}'] = c;
          return c.future;
        },
      );
      final future = repo.refresh(force: true);
      // load() 要读内置和缓存（真实 IO），等两个请求都发出来。
      for (var i = 0; i < 200 && pending.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(pending.keys.toSet(), <String>{
        'cdn.jsdelivr.net/gh/me/jkb@main/latest.json',
        'cdn.jsdelivr.net/gh/me/jkb@main/shu_schedule/assets/holidays.json',
      }, reason: '两个请求都已经发出，谁也没等谁');
      final good = remoteJson();
      pending['cdn.jsdelivr.net/gh/me/jkb@main/latest.json']!.complete(
        jsonEncode(<String, dynamic>{
          'versionCode': 9,
          'versionName': '1.4.0',
          'holidays': <String, dynamic>{'sha256': shaOf(good)},
        }),
      );
      pending['cdn.jsdelivr.net/gh/me/jkb@main/shu_schedule/assets/holidays.json']!
          .complete(good);
      final r = await future;
      expect(r.status, HolidayRefreshStatus.updated);
    });

    test('已经有更新的缓存时，和缓存比（不是和内置比）', () async {
      await cacheFile().writeAsString(remoteJson(updatedAt: '2026-11-02'));
      final r = await repoWith(
        fetch: (_, _) async => remoteJson(updatedAt: '2026-11-02'),
      ).refresh(force: true, manifest: noSha);
      expect(r.status, HolidayRefreshStatus.unchanged);
      expect(r.presets!.source, HolidayDataSource.remote);
    });

    test('全部失败（异常 / 坏 JSON / 版本不对 / 太大 / 超时）→ failed，不抛、不写缓存', () async {
      final r = await repoWith(
        repo: withGitee,
        fetch: (uri, _) async {
          if (uri.host == 'gitee.com') return '<html>404</html>';
          if (uri.host == 'cdn.jsdelivr.net') return remoteJson(version: 2);
          throw Exception('断网');
        },
      ).refresh(force: true, manifest: noSha);
      expect(r.status, HolidayRefreshStatus.failed);
      expect(r.errors, hasLength(3));
      expect(r.errors[1], contains('version'));
      expect(cacheFile().existsSync(), isFalse);

      final big = await repoWith(
        maxBytes: 100,
        fetch: (_, _) async => remoteJson(),
      ).refresh(force: true, manifest: noSha);
      expect(big.status, HolidayRefreshStatus.failed);
      expect(big.errors.first, contains('KiB'));

      final hang = await repoWith(
        timeout: const Duration(milliseconds: 30),
        fetch: (_, _) => Completer<String>().future,
      ).refresh(force: true, manifest: noSha);
      expect(hang.status, HolidayRefreshStatus.failed);
      expect(hang.errors, everyElement(contains('超时')));
    });

    test('latest.json 带 holidays.sha256：一致才接受，不一致就拒绝并试下一个地址', () async {
      final good = remoteJson();
      final tampered = remoteJson(updatedAt: '2026-12-31');
      final manifest = UpdateInfo.fromJson(<String, dynamic>{
        'versionCode': 9,
        'versionName': '1.4.0',
        'holidays': <String, dynamic>{'sha256': shaOf(good)},
      });

      final mismatch = await repoWith(fetch: (_, _) async => tampered)
          .refresh(force: true, manifest: manifest);
      expect(mismatch.status, HolidayRefreshStatus.failed);
      expect(mismatch.errors, everyElement(contains('SHA-256')));
      expect(cacheFile().existsSync(), isFalse);

      final secondOk = await repoWith(
        fetch: (uri, _) async =>
            uri.host == 'cdn.jsdelivr.net' ? tampered : good,
      ).refresh(force: true, manifest: manifest);
      expect(secondOk.status, HolidayRefreshStatus.updated);
      expect(secondOk.source!.host, 'raw.githubusercontent.com');
      expect(cacheFile().readAsStringSync(), good);
    });

    test('没传 manifest：自己读 latest.json 拿 holidays.sha256；读不到就只靠 TLS', () async {
      final good = remoteJson();
      final requested = <String>[];
      String latest(String sha) => jsonEncode(<String, dynamic>{
        'versionCode': 9,
        'versionName': '1.4.0',
        'holidays': <String, dynamic>{'sha256': sha},
      });

      final rejected = await repoWith(
        fetch: (uri, _) async {
          requested.add(uri.pathSegments.last);
          return uri.path.endsWith('latest.json') ? latest('0' * 64) : good;
        },
      ).refresh(force: true);
      expect(rejected.status, HolidayRefreshStatus.failed);
      expect(requested.first, 'latest.json');

      final accepted = await repoWith(
        fetch: (uri, _) async =>
            uri.path.endsWith('latest.json') ? latest(shaOf(good)) : good,
      ).refresh(force: true);
      expect(accepted.status, HolidayRefreshStatus.updated);

      await cacheFile().delete();
      final noManifest = await repoWith(
        fetch: (uri, _) async {
          if (uri.path.endsWith('latest.json')) throw Exception('404');
          return good;
        },
      ).refresh(force: true);
      expect(noManifest.status, HolidayRefreshStatus.updated);
    });
  });

  group('latest.json 口径（tool/gen_latest.py）', () {
    test('脚本对文件原始字节算 SHA-256；App 对下载文本 UTF-8 编码后算——两者一致', () {
      final file = File('assets/holidays.json');
      final fromBytes = crypto.sha256
          .convert(file.readAsBytesSync())
          .toString();
      expect(shaOf(file.readAsStringSync()), fromBytes);
      final raw = file.readAsBytesSync();
      expect(raw.take(3).toList(), isNot(<int>[0xEF, 0xBB, 0xBF]));
      expect(raw.contains(13), isFalse, reason: 'holidays.json 要保持 LF 换行');
    });

    test('脚本生成的 latest.json（多出 apks / holidays 字段）App 能读', () {
      final info = UpdateInfo.fromJson(<String, dynamic>{
        'versionCode': 9,
        'versionName': '1.4.0',
        'changelog': '新增上课提醒\n新增 ICS 导出',
        'downloadUrls': <String>[
          'https://gitee.com/me-cn/jkb/releases/tag/v1.4.0',
          'https://github.com/me/jkb/releases/tag/v1.4.0',
        ],
        'sha256': 'b' * 64,
        'apks': <dynamic>[
          <String, dynamic>{
            'file': '简课表-v1.4.0-arm64.apk',
            'abi': 'arm64-v8a',
            'bytes': 21000000,
            'sha256': 'b' * 64,
          },
        ],
        'holidays': <String, dynamic>{
          'sha256': 'c' * 64,
          'updatedAt': '2026-10-06',
          'bytes': 3117,
        },
      });
      expect(info.versionCode, 9);
      expect(info.sha256, 'b' * 64);
      expect(info.holidaysSha256, 'c' * 64);
      expect(info.downloadUrls.first, startsWith('https://gitee.com/'));
    });

    test('tool/gen_latest.py 在，并且从 repo_config.dart 读 kRepo', () {
      final script = File('tool/gen_latest.py').readAsStringSync();
      expect(script, contains('repo_config.dart'));
      expect(script, contains('"holidays": holidays'));
      expect(script, contains('256 * 1024'));
    });
  });

  group('AppSettings.lastHolidayRefresh 与 refreshFor', () {
    test('旧 settings.json 没有这个字段 → null；JSON 往返；脏数据容错', () {
      final old = AppSettings.fromJson(<String, dynamic>{
        'currentTimetableId': 'a',
        'settingsVersion': 2,
      });
      expect(old.lastHolidayRefresh, isNull);
      final t = DateTime(2026, 10, 7, 8, 30);
      final back = AppSettings.fromJson(
        jsonDecode(jsonEncode(AppSettings(lastHolidayRefresh: t).toJson()))
            as Map<String, dynamic>,
      );
      expect(back.lastHolidayRefresh, t);
      expect(
        AppSettings.fromJson(<String, dynamic>{'lastHolidayRefresh': 42})
            .lastHolidayRefresh,
        isNull,
      );
      expect(
        AppSettings(lastHolidayRefresh: t).copyWith().lastHolidayRefresh,
        t,
      );
    });

    group('需要真实存储', () {
      final storage = TempStorage();
      setUp(() => storage.setUp('holiday_repository_state'));
      tearDown(storage.tearDown);

      test('恢复备份保留设备上的假日表刷新时间', () async {
        final state = AppState();
        await state.load();
        final t = DateTime(2026, 10, 7, 7);
        await state.setLastHolidayRefresh(t);
        final snap = Storage.importJson(
          File('test/fixtures/v1_2_0/backup_v1.json').readAsStringSync(),
        );
        expect(snap.settings.lastHolidayRefresh, isNull);
        await state.restoreFrom(snap);
        expect(state.settings.lastHolidayRefresh, t);
      });

      test('Storage.dataDirectory 尊重 overrideDirectory；默认仓库的缓存就放在那里', () async {
        final d = await Storage.dataDirectory();
        expect(d.path, storage.dir.path);
        final repo = HolidayRepository(
          repo: configured,
          fetch: (_, _) async => remoteJson(),
          loadBundled: () async => bundled,
        );
        final r = await repo.refresh(force: true, manifest: noSha);
        expect(r.status, HolidayRefreshStatus.updated);
        expect(
          File(
            '${storage.dir.path}${Platform.pathSeparator}'
            '${HolidayRepository.cacheFileName}',
          ).existsSync(),
          isTrue,
        );
      });

      test('refreshFor：刷新后写回刷新时间、之后被节流', () async {
        final state = AppState();
        await state.load();
        var calls = 0;
        final repo = HolidayRepository(
          repo: configured,
          fetch: (_, _) async {
            calls++;
            return remoteJson();
          },
          dirProvider: () => dir,
          loadBundled: () async => bundled,
        );
        final now = DateTime(2026, 11, 3, 8);

        final first = await repo.refreshFor(state, now: now, manifest: noSha);
        // （失败不写回时间见「失败不记刷新时间」与下面 refreshFor 失败的用例。）
        expect(first.status, HolidayRefreshStatus.updated);
        expect(state.settings.lastHolidayRefresh, now);
        expect(calls, 1);

        final again = await repo.refreshFor(
          state,
          now: DateTime(2026, 11, 3, 20),
          manifest: noSha,
        );
        expect(again.status, HolidayRefreshStatus.throttled);
        expect(calls, 1);
      });

      test('refreshFor 失败：不写回刷新时间，下次还会再试（fixlist ①）', () async {
        final state = AppState();
        await state.load();
        var calls = 0;
        final repo = HolidayRepository(
          repo: configured,
          fetch: (_, _) async {
            calls++;
            throw Exception('断网');
          },
          dirProvider: () => dir,
          loadBundled: () async => bundled,
        );
        final now = DateTime(2026, 11, 3, 8);
        final r = await repo.refreshFor(state, now: now, manifest: noSha);
        expect(r.status, HolidayRefreshStatus.failed);
        expect(state.settings.lastHolidayRefresh, isNull);
        final again = await repo.refreshFor(
          state,
          now: DateTime(2026, 11, 3, 9),
          manifest: noSha,
        );
        expect(again.status, HolidayRefreshStatus.failed, reason: '没被节流');
        expect(calls, 4, reason: '两次各试 jsDelivr、GitHub raw');
      });
    });
  });
}
