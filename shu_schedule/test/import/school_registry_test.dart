import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/features/import/adapters/school_adapter.dart';
import 'package:shu_schedule/features/import/adapters/school_registry.dart';
import 'package:shu_schedule/features/import/adapters/zfsoft_adapter.dart';

/// 读不到任何 asset 的 bundle：用来测 [SchoolRegistry.fallbackJson] 兜底。
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw Exception('asset not found: $key');
}

/// 返回固定内容的 bundle。
class _FixedBundle extends CachingAssetBundle {
  _FixedBundle(this.text);
  final String text;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.sublistView(bytes);
  }
}

const String _threeSchools = '''
{"version":1,"schools":[
 {"id":"exp","name":"实验大学","pinyin":"shi yan da xue","type":"zfsoft",
  "entryUrl":"https://jw.exp.edu.cn/","baseUrl":"https://jw.exp.edu.cn/jwglxt",
  "status":"experimental"},
 {"id":"com","name":"社区学院","pinyin":"she qu xue yuan","aliases":["社院"],"type":"zfsoft",
  "entryUrl":"https://jw.com.edu.cn/","baseUrl":"https://jw.com.edu.cn/jwglxt/",
  "allowedHosts":["JW.com.edu.cn","sso.com.edu.cn"],
  "overrides":{"homeUrl":"https://jw.com.edu.cn/jwglxt/xtgl/index_initMenu.html",
   "userAgent":"UA-X","description":"社区报告可用",
   "termPresets":[{"id":"t1","name":"2026 秋","startDate":"2026-09-07","totalWeeks":20},
                  {"name":"坏的","startDate":"不是日期"}]},
  "periodProfileId":"default-12","status":"community"},
 {"id":"shu","name":"上海大学","pinyin":"shang hai da xue","aliases":["上大","SHU"],
  "type":"zfsoft","entryUrl":"https://jwxt.shu.edu.cn/",
  "baseUrl":"https://jwxt.shu.edu.cn/jwglxt","allowedHosts":["jwxt.shu.edu.cn"],
  "status":"verified"},
 {"id":"bad","name":"缺 baseUrl","type":"zfsoft"},
 {"id":"shu","name":"重复的上大","type":"zfsoft","baseUrl":"https://x.edu.cn/jwglxt"},
 {"id":"qz","name":"强智学院","type":"qiangzhi","baseUrl":"https://qz.edu.cn/jsxsd","status":"garbage"}
]}
''';

void main() {
  // rootBundle 需要 binding；不初始化的话 ensureLoaded 会静默走兜底清单。
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(SchoolRegistry.resetForTest);
  tearDown(SchoolRegistry.resetForTest);

  group('assets/schools.json', () {
    test('ensureLoaded 从真实 asset 加载：上大是唯一 verified 条目', () async {
      await SchoolRegistry.ensureLoaded();
      expect(SchoolRegistry.isLoaded, isTrue);
      final verified = SchoolRegistry.entries
          .where((e) => e.status == SchoolStatus.verified)
          .toList();
      expect(verified.map((e) => e.id), <String>['shu']);
      final shu = SchoolRegistry.byId('shu')!;
      expect(shu.name, '上海大学');
      expect(shu.type, 'zfsoft');
      expect(shu.allowedHosts, <String>['jwxt.shu.edu.cn']);
      expect(SchoolRegistry.lastLoadWarnings, isEmpty);
      // 确认读的是 asset 而不是兜底清单（兜底清单没有 description / 预设）。
      expect(shu.description, contains('正方教务'));
      expect(shu.termPresets, isNotNull);
    });

    test('上大生成的适配器与 1.2.0 写死的配置一致', () async {
      await SchoolRegistry.ensureLoaded();
      final a = SchoolRegistry.adapterFor('shu')! as ZfsoftAdapter;
      expect(a.baseUrl, 'https://jwxt.shu.edu.cn/jwglxt');
      expect(a.homeUrl, 'https://jwxt.shu.edu.cn/');
      expect(a.loginUrl, 'https://jwxt.shu.edu.cn/');
      expect(a.systemType, 'zfsoft');
      expect(a.captureMode, CaptureMode.fetch);
      expect(a.allowedHosts, <String>['jwxt.shu.edu.cn']);
      expect(a.periodProfileId, 'default-12');
      // 校历预设只作为快捷选项，来自 schools.json 而不是写死在代码里。
      expect(a.presets!.map((p) => p.startDate), <DateTime>[
        DateTime(2026, 9, 14),
        DateTime(2027, 2, 22),
      ]);
      expect(a.sourceTag, 'zfsoft-shu');
    });

    test('代码里的兜底清单和 asset 里的上大条目关键字段一致', () {
      final assetText = File('assets/schools.json').readAsStringSync();
      SchoolRegistry.loadFromJson(assetText);
      final fromAsset = SchoolRegistry.byId('shu')!;
      SchoolRegistry.loadFromJson(SchoolRegistry.fallbackJson);
      final fromFallback = SchoolRegistry.byId('shu')!;
      expect(SchoolRegistry.entries.length, 1);
      expect(fromFallback.name, fromAsset.name);
      expect(fromFallback.type, fromAsset.type);
      expect(fromFallback.entryUrl, fromAsset.entryUrl);
      expect(fromFallback.baseUrl, fromAsset.baseUrl);
      expect(fromFallback.allowedHosts, fromAsset.allowedHosts);
      expect(fromFallback.status, fromAsset.status);
      expect(fromFallback.periodProfileId, fromAsset.periodProfileId);
    });

    test('asset 读不到时退回兜底清单', () async {
      await SchoolRegistry.ensureLoaded(bundle: _BrokenBundle());
      expect(SchoolRegistry.byId('shu'), isNotNull);
      expect(SchoolRegistry.entries.length, 1);
    });

    test('asset 内容是坏 JSON 时也退回兜底清单', () async {
      await SchoolRegistry.ensureLoaded(bundle: _FixedBundle('{oops'));
      expect(SchoolRegistry.byId('shu'), isNotNull);
    });

    test('只加载一次并缓存', () async {
      final bundle = _FixedBundle(_threeSchools);
      await Future.wait(<Future<void>>[
        SchoolRegistry.ensureLoaded(bundle: bundle),
        SchoolRegistry.ensureLoaded(bundle: bundle),
      ]);
      await SchoolRegistry.ensureLoaded(bundle: bundle);
      expect(bundle.loads, 1);
      expect(SchoolRegistry.byId('com'), isNotNull);
    });

    test('未加载时 byId / search 不崩，返回空', () {
      expect(SchoolRegistry.isLoaded, isFalse);
      expect(SchoolRegistry.byId('shu'), isNull);
      expect(SchoolRegistry.search(''), isEmpty);
    });
  });

  group('loadFromJson', () {
    setUp(() => SchoolRegistry.loadFromJson(_threeSchools));

    test('坏条目、重复 id 被丢掉并记 warning', () {
      expect(SchoolRegistry.entries.map((e) => e.id), <String>[
        'exp',
        'com',
        'shu',
        'qz',
      ]);
      expect(SchoolRegistry.byId('shu')!.name, '上海大学', reason: '重复 id 保留第一条');
      expect(SchoolRegistry.lastLoadWarnings.length, 2);
    });

    test('status 解析：不认识的值当 experimental', () {
      expect(SchoolRegistry.byId('shu')!.status, SchoolStatus.verified);
      expect(SchoolRegistry.byId('com')!.status, SchoolStatus.community);
      expect(SchoolRegistry.byId('exp')!.status, SchoolStatus.experimental);
      expect(SchoolRegistry.byId('qz')!.status, SchoolStatus.experimental);
      expect(SchoolStatus.verified.label, '已验证');
      expect(SchoolStatus.community.label, '社区');
      expect(SchoolStatus.experimental.label, '实验');
    });

    test('overrides 映射到适配器：homeUrl / userAgent / 预设 / allowedHosts 归一化', () {
      final a = SchoolRegistry.adapterFor('com')! as ZfsoftAdapter;
      expect(a.baseUrl, 'https://jw.com.edu.cn/jwglxt', reason: '去掉尾斜杠');
      expect(a.loginUrl, 'https://jw.com.edu.cn/');
      expect(
        a.homeUrl,
        'https://jw.com.edu.cn/jwglxt/xtgl/index_initMenu.html',
      );
      expect(a.userAgent, 'UA-X');
      expect(a.description, '社区报告可用');
      expect(a.allowedHosts, <String>['jw.com.edu.cn', 'sso.com.edu.cn']);
      expect(a.presets!.single.name, '2026 秋', reason: '坏的预设被丢掉');
      expect(a.presets!.single.totalWeeks, 20);
      expect(a.sourceTag, 'zfsoft-com');
    });

    test('没写 allowedHosts 时退回 baseUrl 的 host', () {
      final a = SchoolRegistry.adapterFor('exp')!;
      expect(a.allowedHosts, <String>['jw.exp.edu.cn']);
      expect(a.isAllowedHost('https://jw.exp.edu.cn/jwglxt/x'), isTrue);
      expect(a.isAllowedHost('https://sso.exp.edu.cn/login'), isFalse);
      expect(a.presets, isNull);
    });

    test('不支持的系统类型：条目在，但生成不了适配器', () {
      expect(SchoolRegistry.byId('qz'), isNotNull);
      expect(SchoolRegistry.adapterFor('qz'), isNull);
    });

    test('allowedHosts 决定登录判定', () {
      final a = SchoolRegistry.adapterFor('com')!;
      expect(
        a.isLoggedIn('https://jw.com.edu.cn/jwglxt/xtgl/index.html'),
        isTrue,
      );
      expect(
        a.isLoggedIn('https://sso.com.edu.cn/jwglxt/xtgl/index.html'),
        isTrue,
      );
      expect(a.isLoggedIn('https://evil.example.com/jwglxt/'), isFalse);
    });
  });

  group('search', () {
    setUp(() => SchoolRegistry.loadFromJson(_threeSchools));

    List<String> ids(String q) =>
        SchoolRegistry.search(q).map((e) => e.id).toList();

    test('空查询返回全部，已验证 > 社区 > 实验，同档保持清单顺序', () {
      expect(ids(''), <String>['shu', 'com', 'exp', 'qz']);
    });

    test('按名称 / id / 别名', () {
      expect(ids('上海'), <String>['shu']);
      expect(ids('SHU'), <String>['shu']);
      expect(ids('上大'), <String>['shu']);
      expect(ids('社院'), <String>['com']);
      expect(ids('清华'), isEmpty);
    });

    test('按拼音连写与首字母，大小写 / 空格不敏感', () {
      expect(ids('shanghai'), <String>['shu']);
      expect(ids('ShangHai DaXue'), <String>['shu']);
      expect(ids('shdx'), <String>['shu']);
      expect(ids('sqxy'), <String>['com']);
      expect(ids('daxue'), <String>['shu', 'exp']);
    });
  });

  group('SchoolUrlGuess.fromUrl（我的学校不在列表）', () {
    test('含 /jwglxt → 正方新版临时 experimental 条目', () {
      final g = SchoolUrlGuess.fromUrl(
        '  https://JWGL.Example.edu.cn/jwglxt/xtgl/login_slogin.html?time=1#top ',
      );
      expect(g.supported, isTrue);
      final e = g.entry!;
      expect(e.type, 'zfsoft');
      expect(e.status, SchoolStatus.experimental);
      expect(e.baseUrl, 'https://jwgl.example.edu.cn/jwglxt');
      expect(e.allowedHosts, <String>['jwgl.example.edu.cn']);
      expect(e.id, 'custom-jwgl.example.edu.cn');
      final a = e.buildAdapter()! as ZfsoftAdapter;
      expect(a.homeUrl, 'https://jwgl.example.edu.cn/');
      expect(
        a.loginUrl,
        'https://jwgl.example.edu.cn/jwglxt/xtgl/login_slogin.html?time=1',
        reason: '入口用用户给的地址（去掉 #fragment）',
      );
      expect(a.baseUrl, 'https://jwgl.example.edu.cn/jwglxt');
      expect(g.message, isNull);
    });

    test('带端口、路径前缀、没写 scheme', () {
      final g = SchoolUrlGuess.fromUrl('jw.abc.edu.cn:8080/xs/JWGLXT');
      final e = g.entry!;
      expect(e.baseUrl, 'https://jw.abc.edu.cn:8080/xs/JWGLXT');
      expect(e.buildAdapter()!.homeUrl, 'https://jw.abc.edu.cn:8080/');
      expect(e.allowedHosts, <String>['jw.abc.edu.cn']);
    });

    test('http 且不在 edu.cn 下：能生成，但提醒可能被系统拦截', () {
      final g = SchoolUrlGuess.fromUrl('http://10.1.2.3/jwglxt/');
      expect(g.supported, isTrue);
      expect(g.entry!.baseUrl, 'http://10.1.2.3/jwglxt');
      expect(g.message, contains('明文'));
      expect(
        SchoolUrlGuess.fromUrl('http://jw.x.edu.cn/jwglxt').message,
        isNull,
        reason: 'edu.cn 的明文已放行',
      );
    });

    test('/jwglxt 必须是完整的一段路径', () {
      expect(
        SchoolUrlGuess.fromUrl('https://a.edu.cn/jwglxtx/').supported,
        isFalse,
      );
      expect(
        SchoolUrlGuess.fromUrl('https://a.edu.cn/x/jwglxt').supported,
        isTrue,
      );
    });

    test('认不出的系统 / 非法输入 → 不支持并给出原因', () {
      for (final input in <String>[
        'https://jw.abc.edu.cn/jsxsd/xskb/xskb_list.do',
        'https://jw.abc.edu.cn/eams/courseTableForStd.action',
        '',
        'ftp://jw.abc.edu.cn/jwglxt',
        'weixin://jwglxt',
      ]) {
        final g = SchoolUrlGuess.fromUrl(input);
        expect(g.supported, isFalse, reason: input);
        expect(g.message, isNotNull, reason: input);
      }
    });

    test('生成的适配器默认用第一套作息模板', () {
      final a = SchoolUrlGuess.fromUrl('https://a.edu.cn/jwglxt').entry!
          .buildAdapter()!;
      expect(a.periodProfileId, periodTemplates.first.id);
      expect(a.sourceTag, 'zfsoft-custom-a.edu.cn');
    });
  });
}
