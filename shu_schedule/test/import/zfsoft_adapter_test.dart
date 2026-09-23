import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/features/import/adapters/school_adapter.dart';
import 'package:shu_schedule/features/import/adapters/zfsoft_adapter.dart';
import 'package:shu_schedule/models/course.dart';

/// fixtures 目录（`flutter test` 的工作目录是工程根）。
const String _fixtureDir = 'test/import/fixtures';

String _fixture(String name) =>
    File('$_fixtureDir/$name').readAsStringSync(encoding: utf8);

ZfsoftAdapter _shu() => ZfsoftAdapter(
  id: 'shu',
  name: '上海大学',
  baseUrl: 'https://jwxt.shu.edu.cn/jwglxt',
  homeUrl: 'https://jwxt.shu.edu.cn/',
);

Course _byName(List<Course> list, String name) =>
    list.firstWhere((c) => c.name == name);

void main() {
  final adapter = _shu();
  // 固定「现在」：2026-10-01 是周四，所属周的周一是 2026-09-28。
  final now = DateTime(2026, 10, 1);

  group('ZfsoftAdapter.parse —— 正常课表', () {
    late ImportResult result;

    setUp(() {
      result = adapter.parse(_fixture('shu_kb_envelope.json'), now: now);
    });

    test('解析出 8 门有固定时间的课（含合并后的重复项）', () {
      expect(result.courses.length, 8);
      expect(result.courses.map((c) => c.name).toSet(), <String>{
        '高等数学(一)',
        '程序设计基础',
        '大学英语(三)',
        '线性代数',
        '大学物理(一)',
        '形势与政策',
        '体育(羽毛球)',
        '马克思主义基本原理',
      });
    });

    test('课程按星期、节次排序', () {
      final keys = result.courses
          .map((c) => c.day * 100 + c.startPeriod)
          .toList();
      final sorted = List<int>.from(keys)..sort();
      expect(keys, sorted);
    });

    test('基础字段映射：kcmc/xm/cdmc/xqj/jcs', () {
      final math = _byName(result.courses, '高等数学(一)');
      expect(math.teacher, '王建国');
      expect(math.location, 'A楼101');
      expect(math.day, 1);
      expect(math.startPeriod, 1);
      expect(math.endPeriod, 2);
      expect(math.source, 'zfsoft-shu');
      expect(math.weeks, List<int>.generate(16, (i) => i + 1));
    });

    test('结果带上学校 / 系统 / 学期代码，来源标记 = systemType-schoolId', () {
      expect(result.schoolId, 'shu');
      expect(result.systemType, 'zfsoft');
      expect(result.sourceTag, 'zfsoft-shu');
      expect(result.termCode, '2026-2027-1');
      expect(result.detectedPeriods, isNull, reason: '正方课表接口不带节次时刻');
    });

    test('每门课都有 groupId 与唯一的 externalKey', () {
      final keys = result.courses.map((c) => c.externalKey).toList();
      expect(keys.every((k) => k != null && k.isNotEmpty), isTrue);
      expect(keys.toSet().length, keys.length);
      final math = _byName(result.courses, '高等数学(一)');
      expect(math.externalKey, startsWith('01011001|高等数学(一)-01|1|1-2'));
      expect(math.groupId, startsWith('zfsoft-shu-g-'));
      // 不同的课 groupId 不同。
      final groups = result.courses.map((c) => c.groupId).toSet();
      expect(groups.length, greaterThan(1));
    });

    test('zcd = 1-15周(单) → 只有奇数周', () {
      final english = _byName(result.courses, '大学英语(三)');
      expect(english.weeks, <int>[1, 3, 5, 7, 9, 11, 13, 15]);
      expect(english.day, 2);
    });

    test('zcd = 2-16周(双) → 只有偶数周', () {
      final linear = _byName(result.courses, '线性代数');
      expect(linear.weeks, <int>[2, 4, 6, 8, 10, 12, 14, 16]);
      // xqj 是数字 3 而不是字符串，也要能解析。
      expect(linear.day, 3);
    });

    test('zcd = 1-8周,10-16周 → 多段', () {
      final physics = _byName(result.courses, '大学物理(一)');
      expect(physics.weeks, <int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ]);
      expect(physics.startPeriod, 7);
      expect(physics.endPeriod, 8);
    });

    test('zcd = 3周 → 单周', () {
      final policy = _byName(result.courses, '形势与政策');
      expect(policy.weeks, <int>[3]);
    });

    test('周六课（xqj=6）与缺 cdmc 的课都能导入', () {
      final pe = _byName(result.courses, '体育(羽毛球)');
      expect(pe.day, 6);
      expect(pe.location, isNull);
      expect(pe.teacher, '周涛');
    });

    test('只有 jc 没有 jcs 时也能解析节次', () {
      final marx = _byName(result.courses, '马克思主义基本原理');
      expect(marx.day, 7);
      expect(marx.startPeriod, 11);
      expect(marx.endPeriod, 12);
    });

    test('同名同师同地同星期同节次的两条记录合并周次', () {
      final pd = result.courses.where((c) => c.name == '程序设计基础').toList();
      expect(pd.length, 1);
      expect(pd.single.weeks, <int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ]);
    });

    test('脏数据被跳过并写进 warnings', () {
      expect(result.courses.any((c) => c.name == '星期越界课'), isFalse);
      expect(result.courses.any((c) => c.name == '周次为空课'), isFalse);
      expect(result.courses.any((c) => c.name == '节次为空课'), isFalse);
      // 缺 kcmc / xqj=9 / zcd 空 / 节次空，共 4 条。
      expect(result.warnings.length, 4);
      expect(result.warnings.any((w) => w.contains('没有课程名')), isTrue);
      expect(result.warnings.any((w) => w.contains('星期字段异常')), isTrue);
      expect(result.warnings.any((w) => w.contains('周次文本无法解析')), isTrue);
      expect(result.warnings.any((w) => w.contains('节次字段无法解析')), isTrue);
    });

    test('sjkList → unscheduled，不进网格', () {
      expect(result.unscheduled.length, 1);
      final c = result.unscheduled.single;
      expect(c.name, '创新创业实践');
      expect(c.teacher, '陈明');
      expect(c.location, isNull, reason: 'cdmc 是空串应当归一化成 null');
      expect(c.day, 0, reason: 'day=0 表示没有固定星期，不会进网格');
      expect(c.note, contains('线上自主学习'));
      expect(result.courses.any((c) => c.name == '创新创业实践'), isFalse);
    });

    test('学期信息与学生姓名', () {
      expect(result.termName, '2026-2027 秋');
      expect(result.rawTermName, '2026-2027学年 秋季学期');
      expect(result.studentName, '张三');
    });

    test('课程 id 唯一', () {
      final ids = result.courses.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('周次检测与开学日期推断', () {
    test('currentWeek=3 → 开学日期 = 本周周一往前 2 周', () {
      final result = adapter.parse(_fixture('shu_kb_envelope.json'), now: now);
      expect(result.detectedCurrentWeek, 3);
      // 2026-10-01 是周四 → 本周周一 2026-09-28 → 减 14 天 = 2026-09-14。
      expect(result.detectedStartDate, DateTime(2026, 9, 14));
    });

    test('周一当天也算本周', () {
      final result = adapter.parse(
        _fixture('shu_kb_envelope.json'),
        now: DateTime(2026, 9, 28),
      );
      expect(result.detectedStartDate, DateTime(2026, 9, 14));
    });

    test('周日当天仍算本周（周日 weekday=7）', () {
      final result = adapter.parse(
        _fixture('shu_kb_envelope.json'),
        now: DateTime(2026, 10, 4),
      );
      expect(result.detectedStartDate, DateTime(2026, 9, 14));
    });

    test('第 1 周 → 开学日期就是本周周一', () {
      final raw = _withCurrentWeek(1);
      final result = adapter.parse(raw, now: DateTime(2026, 9, 16));
      expect(result.detectedStartDate, DateTime(2026, 9, 14));
    });

    test('拿不到周次 → 不再猜任何学校的校历，开学日期留空并给出 warning', () {
      final result = adapter.parse(_withoutCurrentWeek(), now: now);
      expect(result.detectedCurrentWeek, isNull);
      expect(result.detectedStartDate, isNull);
      expect(
        result.warnings.any((w) => w.contains('请在下一步选择本学期第一周的周一')),
        isTrue,
      );
    });

    test('周次越界（0 / 999）当作没拿到', () {
      for (final bad in <int>[0, 999]) {
        final result = adapter.parse(_withCurrentWeek(bad), now: now);
        expect(result.detectedCurrentWeek, isNull, reason: 'week=$bad');
      }
    });

    test('termCodeOf：xnm/xqm → 学年学期代码', () {
      expect(ZfsoftAdapter.termCodeOf('2026', '3'), '2026-2027-1');
      expect(ZfsoftAdapter.termCodeOf('2026', '12'), '2026-2027-2');
      expect(ZfsoftAdapter.termCodeOf('2026', '16'), '2026-2027-3');
      expect(ZfsoftAdapter.termCodeOf('2026', '99'), '2026-2027-99');
      expect(ZfsoftAdapter.termCodeOf('2026', null), '2026-2027');
      expect(ZfsoftAdapter.termCodeOf(null, '3'), isNull);
    });

    test('推断出的开学日期一定是周一', () {
      for (var week = 1; week <= 20; week++) {
        final result = adapter.parse(_withCurrentWeek(week), now: now);
        expect(result.detectedStartDate!.weekday, DateTime.monday);
        expect(
          ScheduleUtils.daysBetween(result.detectedStartDate!, now) ~/ 7 + 1,
          week,
        );
      }
    });
  });

  group('学期默认值推断', () {
    test('termNameOf 把 xnm/xqm 翻译成中文学期名', () {
      expect(ZfsoftAdapter.termNameOf('2026', '3'), '2026-2027 秋');
      expect(ZfsoftAdapter.termNameOf('2026', '12'), '2026-2027 春');
      expect(ZfsoftAdapter.termNameOf('2026', '16'), '2026-2027 夏');
      expect(ZfsoftAdapter.termNameOf('2026', null), '2026-2027');
      expect(ZfsoftAdapter.termNameOf(null, '3'), '秋');
      expect(ZfsoftAdapter.termNameOf('不是年份', '99'), isNull);
    });

    test('fallbackXnm：9 月及以后取今年，否则取去年', () {
      expect(ZfsoftAdapter.fallbackXnm(DateTime(2026, 9, 1)), '2026');
      expect(ZfsoftAdapter.fallbackXnm(DateTime(2026, 12, 31)), '2026');
      expect(ZfsoftAdapter.fallbackXnm(DateTime(2026, 8, 31)), '2025');
      expect(ZfsoftAdapter.fallbackXnm(DateTime(2026, 1, 5)), '2025');
    });

    test('payload 缺 xnm/xqm 时退回 xsxx，再退回按日期推断', () {
      // 只留 xsxx 的 XNM/XQM。
      final data = _data();
      data.remove('xnm');
      data.remove('xqm');
      final viaXsxx = adapter.parse(_encode(data), now: now);
      expect(viaXsxx.termName, '2026-2027 秋');

      // xsxx 也没有 → 按 now 推断，并给出 warning。
      final kb = Map<String, dynamic>.from(data['kb'] as Map);
      final xsxx = Map<String, dynamic>.from(kb['xsxx'] as Map)
        ..remove('XNM')
        ..remove('XQM');
      kb['xsxx'] = xsxx;
      data['kb'] = kb;
      final inferred = adapter.parse(_encode(data), now: DateTime(2026, 10, 1));
      expect(inferred.termName, '2026-2027 秋');
      expect(
        inferred.warnings.any((w) => w.contains('未能读取教务系统的学年默认值')),
        isTrue,
      );
    });

    test('把课表接口的裸响应直接丢进来也能解析', () {
      final kb = (_data()['kb'] as Map).cast<String, dynamic>();
      final result = adapter.parse(jsonEncode(kb), now: now);
      expect(result.courses.length, 8);
      expect(result.termName, '2026-2027 秋');
      // 没有 currentWeek → 回退预设。
      expect(result.detectedCurrentWeek, isNull);
    });
  });

  group('颜色哈希', () {
    test('同名课程颜色稳定且落在 0..9', () {
      const names = <String>[
        '高等数学(一)',
        '大学英语(三)',
        '线性代数',
        '体育(羽毛球)',
        '马克思主义基本原理',
        '',
      ];
      for (final n in names) {
        final a = ZfsoftAdapter.colorIndexFor(n);
        final b = ZfsoftAdapter.colorIndexFor(n);
        expect(a, b);
        expect(a, inInclusiveRange(0, 9));
      }
    });

    test('解析两次得到完全一致的 colorIndex', () {
      final a = adapter.parse(_fixture('shu_kb_envelope.json'), now: now);
      final b = adapter.parse(_fixture('shu_kb_envelope.json'), now: now);
      expect(
        a.courses.map((c) => '${c.name}:${c.colorIndex}').toList(),
        b.courses.map((c) => '${c.name}:${c.colorIndex}').toList(),
      );
    });

    test('不同课程名至少用上了多种颜色', () {
      final result = adapter.parse(_fixture('shu_kb_envelope.json'), now: now);
      final colors = result.courses.map((c) => c.colorIndex).toSet();
      expect(colors.length, greaterThan(1));
    });

    test('同名课程合并后颜色与单独计算一致', () {
      final result = adapter.parse(_fixture('shu_kb_envelope.json'), now: now);
      final pd = _byName(result.courses, '程序设计基础');
      expect(pd.colorIndex, ZfsoftAdapter.colorIndexFor('程序设计基础'));
    });
  });

  group('节次解析', () {
    test('jcs / jc 两种写法', () {
      expect(ZfsoftAdapter.parsePeriodSpan('1-2', null), (1, 2));
      expect(ZfsoftAdapter.parsePeriodSpan(null, '1-2节'), (1, 2));
      expect(ZfsoftAdapter.parsePeriodSpan(null, '第11-12节'), (11, 12));
      expect(ZfsoftAdapter.parsePeriodSpan('3', null), (3, 3));
      expect(ZfsoftAdapter.parsePeriodSpan('4-3', null), (3, 4));
    });

    test('无法解析时返回 null，不抛异常', () {
      expect(ZfsoftAdapter.parsePeriodSpan(null, null), isNull);
      expect(ZfsoftAdapter.parsePeriodSpan('无', '未安排'), isNull);
      expect(ZfsoftAdapter.parsePeriodSpan('0-2', null), isNull);
    });

    test('越界节次被裁剪到 maxPeriod', () {
      expect(ZfsoftAdapter.parsePeriodSpan('1-999', null), (
        1,
        ZfsoftAdapter.maxPeriod,
      ));
    });
  });

  group('错误与登录判定', () {
    test('被踢回登录页的 HTML → 未登录异常', () {
      expect(
        () => adapter.parse(_fixture('shu_login_redirect.html'), now: now),
        throwsA(
          isA<ImportException>().having(
            (e) => e.message,
            'message',
            contains('未登录'),
          ),
        ),
      );
    });

    test('脚本回传 ok:false + __LOGIN__ → 未登录异常', () {
      expect(
        () => adapter.parse(
          '{"ok":false,"stage":"kb","error":"__LOGIN__"}',
          now: now,
        ),
        throwsA(
          isA<ImportException>()
              .having((e) => e.message, 'message', contains('未登录'))
              .having((e) => e.suggestion, 'suggestion', isNotNull),
        ),
      );
    });

    test('脚本回传 __NOTJSON__ → 接口变化提示', () {
      expect(
        () => adapter.parse(
          '{"ok":false,"stage":"kb","error":"__NOTJSON__"}',
          now: now,
        ),
        throwsA(
          isA<ImportException>().having(
            (e) => e.message,
            'message',
            contains('不是 JSON'),
          ),
        ),
      );
    });

    test('脚本回传任意错误 → 带上原始信息', () {
      expect(
        () => adapter.parse(
          '{"ok":false,"stage":"index","error":"Failed to fetch"}',
          now: now,
        ),
        throwsA(
          isA<ImportException>()
              .having((e) => e.message, 'message', contains('Failed to fetch'))
              .having((e) => e.stage, 'stage', ImportStage.indexPage),
        ),
      );
    });

    test('空串 / 非 Map / 缺 data 都抛 ImportException', () {
      expect(
        () => adapter.parse('', now: now),
        throwsA(isA<ImportException>()),
      );
      expect(
        () => adapter.parse('   ', now: now),
        throwsA(isA<ImportException>()),
      );
      expect(
        () => adapter.parse('[1,2,3]', now: now),
        throwsA(isA<ImportException>()),
      );
      expect(
        () => adapter.parse('{"ok":true}', now: now),
        throwsA(isA<ImportException>()),
      );
    });

    test('课表为空时不抛异常，只给 warning', () {
      final result = adapter.parse(
        '{"ok":true,"data":{"xnm":"2026","xqm":"3","currentWeek":1,'
        '"kb":{"kbList":[],"sjkList":[],"xsxx":{}}}}',
        now: now,
      );
      expect(result.isEmpty, isTrue);
      expect(result.warnings.any((w) => w.contains('没有解析到任何课程')), isTrue);
    });

    test('isLoggedIn 只认 jwxt.shu.edu.cn 下的 /jwglxt/ 非登录页', () {
      expect(
        adapter.isLoggedIn(
          'https://jwxt.shu.edu.cn/jwglxt/xtgl/index_initMenu.html',
        ),
        isTrue,
      );
      expect(
        adapter.isLoggedIn(
          'https://jwxt.shu.edu.cn/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151',
        ),
        isTrue,
      );
      expect(adapter.isLoggedIn('https://jwxt.shu.edu.cn/'), isFalse);
      expect(
        adapter.isLoggedIn(
          'https://jwxt.shu.edu.cn/jwglxt/xtgl/login_slogin.html',
        ),
        isFalse,
      );
      expect(
        adapter.isLoggedIn('https://newsso.shu.edu.cn/login?service=xxx'),
        isFalse,
      );
      expect(adapter.isLoggedIn('about:blank'), isFalse);
      expect(adapter.isLoggedIn(''), isFalse);
    });
  });

  // ----------------------------------------------------------- REVIEW-1 修复

  group('REVIEW-1 H2：__NETWORK__ 分支', () {
    test('脚本回传 __NETWORK__ → 登录失效 / 网络不通提示，而不是「接口变了」', () {
      final envelope = jsonEncode(<String, dynamic>{
        'ok': false,
        'stage': 'kb',
        'error': '__NETWORK__',
      });
      final e = _catchImport(() => adapter.parse(envelope));
      expect(e.message, contains('请求教务接口失败'));
      expect(e.suggestion, contains('VPN'));
      expect(e.stage, ImportStage.schedule);
    });

    test('__NETWORK__ 与 __NOTJSON__ 给的是不同的提示', () {
      final net = _catchImport(
        () => adapter.parse(
          jsonEncode(<String, dynamic>{
            'ok': false,
            'stage': 'kb',
            'error': '__NETWORK__',
          }),
        ),
      );
      final notJson = _catchImport(
        () => adapter.parse(
          jsonEncode(<String, dynamic>{
            'ok': false,
            'stage': 'kb',
            'error': '__NOTJSON__',
          }),
        ),
      );
      expect(net.message == notJson.message, isFalse);
    });

    test('脚本里有 checkLogin / 状态码与跨源跳转判定', () {
      final script = adapter.scrapeScript;
      expect(script, contains('function checkLogin'));
      expect(script, contains('r.status === 401'));
      expect(script, contains('r.redirected'));
      expect(script, contains('__NETWORK__'));
      expect(script, contains("e.name === 'TypeError'"));
    });
  });

  group('REVIEW-1 M2/M3/M4：周次匹配、编码、脚本里不写中文', () {
    test('周次优先匹配「当前…第 N 周」，宽松匹配放最后', () {
      final script = adapter.scrapeScript;
      final currentFirst = script.indexOf(r'\u5f53\u524d[^0-9]{0,6}\u7b2c');
      final loose = script.indexOf(r's.match(/\u7b2c\s*(\d+)\s*\u5468/)');
      expect(currentFirst, greaterThan(0), reason: '要有「当前第 N 周」的优先规则');
      expect(loose, greaterThan(currentFirst), reason: '宽松匹配必须排在后面');
    });

    test('GBK 页面走 TextDecoder 解码', () {
      final script = adapter.scrapeScript;
      expect(script, contains('function decodeBody'));
      expect(script, contains("TextDecoder('gbk')"));
      expect(script, contains("ct.indexOf('gb')"));
    });

    test('脚本的代码部分没有裸中文（字符串/正则一律 \\uXXXX，注释不算）', () {
      // 注释里的中文不会经过 JS 引擎的字符串处理，留着更好读；
      // 有风险的是字符串字面量和正则，所以先把注释剥掉再查。
      final stripped = adapter.scrapeScript
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
      final cjk = RegExp(r'[一-鿿]');
      final offenders = stripped.split('\n').where(cjk.hasMatch).toList();
      expect(offenders, isEmpty, reason: '出现裸中文的行：\n${offenders.join('\n')}');
    });
  });

  group('REVIEW-1 L2：jcs 与 jc 不一致', () {
    test('取跨度更大的那个并给 warning', () {
      final data = _data();
      final kb = Map<String, dynamic>.from(data['kb'] as Map);
      kb['kbList'] = <dynamic>[
        <String, dynamic>{
          'kcmc': '跨度冲突课',
          'xqj': '1',
          'jcs': '1-2',
          'jc': '1-4节',
          'zcd': '1-16周',
        },
      ];
      data['kb'] = kb;
      final result = adapter.parse(_encode(data));
      final course = result.courses.single;
      expect(course.startPeriod, 1);
      expect(course.endPeriod, 4, reason: '取跨度更大的 jc');
      expect(result.warnings.any((w) => w.contains('节次字段不一致')), isTrue);
    });

    test('两者一致时不产生 warning', () {
      expect(ZfsoftAdapter.parsePeriodSpan('3-4', '3-4节'), (3, 4));
      final warnings = <String>[];
      ZfsoftAdapter.parsePeriodSpan('3-4', '3-4节', warnings: warnings);
      expect(warnings, isEmpty);
    });
  });

  group('REVIEW-1 L3：教学班不同不合并', () {
    test('同名同教室同节次但 jxbmc 不同 → 两门课', () {
      final data = _data();
      final kb = Map<String, dynamic>.from(data['kb'] as Map);
      kb['kbList'] = <dynamic>[
        <String, dynamic>{
          'kcmc': '大学英语',
          'xqj': '2',
          'jcs': '1-2',
          'zcd': '1-8周',
          'jxbmc': '英语A班',
        },
        <String, dynamic>{
          'kcmc': '大学英语',
          'xqj': '2',
          'jcs': '1-2',
          'zcd': '9-16周',
          'jxbmc': '英语B班',
        },
      ];
      data['kb'] = kb;
      final result = adapter.parse(_encode(data));
      expect(result.courses.length, 2);
    });

    test('jxbmc 相同则照旧合并周次', () {
      final data = _data();
      final kb = Map<String, dynamic>.from(data['kb'] as Map);
      kb['kbList'] = <dynamic>[
        <String, dynamic>{
          'kcmc': '大学英语',
          'xqj': '2',
          'jcs': '1-2',
          'zcd': '1-8周',
          'jxbmc': '英语A班',
        },
        <String, dynamic>{
          'kcmc': '大学英语',
          'xqj': '2',
          'jcs': '1-2',
          'zcd': '10-16周',
          'jxbmc': '英语A班',
        },
      ];
      data['kb'] = kb;
      final result = adapter.parse(_encode(data));
      expect(result.courses.length, 1);
      expect(result.courses.single.weeks, contains(1));
      expect(result.courses.single.weeks, contains(16));
    });
  });

  group('REVIEW-1 L5：路径没有尾斜杠也算已登录', () {
    test('/jwglxt 与 /jwglxt/ 都认', () {
      expect(adapter.isLoggedIn('https://jwxt.shu.edu.cn/jwglxt'), isTrue);
      expect(adapter.isLoggedIn('https://jwxt.shu.edu.cn/jwglxt/'), isTrue);
      expect(
        adapter.isLoggedIn('https://jwxt.shu.edu.cn/jwglxtother'),
        isFalse,
      );
    });
  });

  group('REVIEW-1 H3：通道消息解析', () {
    test('进度消息只更新阶段', () {
      final m = parseChannelMessage('{"progress":true,"stage":"week"}');
      expect(m.kind, ChannelMessageKind.progress);
      expect(m.stage, ImportStage.week);
    });

    test('终态消息里出现 "progress" 字样也不会被误判成进度', () {
      final raw = jsonEncode(<String, dynamic>{
        'ok': true,
        'stage': 'done',
        'data': <String, dynamic>{
          'kb': <String, dynamic>{
            'kbList': <dynamic>[
              <String, dynamic>{'kcmc': '课程"progress"实验', 'xqj': '1'},
            ],
          },
        },
      });
      expect(raw, contains('progress'));
      expect(parseChannelMessage(raw).kind, ChannelMessageKind.result);
    });

    test('ok:false 也是终态', () {
      expect(
        parseChannelMessage('{"ok":false,"stage":"kb","error":"__LOGIN__"}')
            .kind,
        ChannelMessageKind.result,
      );
    });

    test('非 JSON / 非对象 / 无 ok 键一律忽略（通道对任意页面开放）', () {
      expect(parseChannelMessage('hello').kind, ChannelMessageKind.ignore);
      expect(parseChannelMessage('[1,2,3]').kind, ChannelMessageKind.ignore);
      expect(
        parseChannelMessage('"just a string"').kind,
        ChannelMessageKind.ignore,
      );
      expect(
        parseChannelMessage('{"hello":"world"}').kind,
        ChannelMessageKind.ignore,
      );
      expect(parseChannelMessage('').kind, ChannelMessageKind.ignore);
    });

    test('progress 不是 true 时按终态/忽略处理', () {
      expect(
        parseChannelMessage('{"progress":"yes","ok":true}').kind,
        ChannelMessageKind.result,
      );
      expect(
        parseChannelMessage('{"progress":false}').kind,
        ChannelMessageKind.ignore,
      );
    });
  });

  group('注入脚本', () {
    test('占位符全部被替换，关键接口与通道名都在', () {
      final script = adapter.scrapeScript;
      expect(script.contains('__BASE__'), isFalse);
      expect(script.contains('__CHANNEL__'), isFalse);
      expect(script, contains(importChannelName));
      expect(script, contains('https://jwxt.shu.edu.cn/jwglxt'));
      expect(script, contains('kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N2151'));
      expect(script, contains('kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151'));
      expect(script, contains('xtgl/index_cxAreaSix.html'));
      expect(script, contains('kzlx=ck&xsdm='));
      expect(script, contains("credentials: 'include'"));
      expect(
        script,
        contains(
          "'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'",
        ),
      );
    });

    test('同域时 BASE 会被改写成当前文档的源（http SSO 回跳后不跨源）', () {
      final script = adapter.scrapeScript;
      expect(script, contains('location.protocol'));
      expect(script, contains('location.hostname'));
    });

    test('baseUrl 结尾的斜杠会被去掉，不会出现 //', () {
      final a = ZfsoftAdapter(
        id: 'x',
        name: 'X',
        baseUrl: 'https://example.edu.cn/jwglxt/',
        homeUrl: 'https://example.edu.cn/',
      );
      expect(a.baseUrl, 'https://example.edu.cn/jwglxt');
      expect(a.scrapeScript.contains('jwglxt//'), isFalse);
      expect(a.pathMarker, '/jwglxt/');
      expect(a.expectedHost, 'example.edu.cn');
    });
  });

  group('v1.3.0 泛化', () {
    Map<String, dynamic> kbItem(
      String day,
      String jcs, {
      String cdmc = 'A101',
    }) => <String, dynamic>{
      'kcmc': '线性代数',
      'xm': '赵强',
      'cdmc': cdmc,
      'xqj': day,
      'jcs': jcs,
      'zcd': '1-16周',
      'kch': '01011005',
      'jxbmc': '线性代数-07',
    };

    test('同一门课的多个时段共用 groupId，externalKey 各不相同', () {
      final raw = jsonEncode(<String, dynamic>{
        'kbList': <Map<String, dynamic>>[
          kbItem('2', '1-2'),
          kbItem('4', '3-4'),
          // 同一时段换了教室 → 拆成两条，外部键加序号。
          kbItem('4', '3-4', cdmc: 'B202'),
        ],
      });
      final r = adapter.parse(raw, now: now);
      expect(r.courses.length, 3);
      expect(r.courses.map((c) => c.groupId).toSet().length, 1);
      final keys = r.courses.map((c) => c.externalKey!).toList();
      expect(keys.toSet().length, 3);
      expect(keys, contains('01011005|线性代数-07|2|1-2'));
      expect(keys, contains('01011005|线性代数-07|4|3-4'));
      expect(keys, contains('01011005|线性代数-07|4|3-4#2'));
    });

    test('课程号不同的课 groupId 不同；没有 kch 时按课程名分组', () {
      final a = kbItem('1', '1-2');
      final b = kbItem('1', '3-4')..['kch'] = '99999999';
      final c = kbItem('3', '5-6')..remove('kch');
      final r = adapter.parse(
        jsonEncode(<String, dynamic>{
          'kbList': <Map<String, dynamic>>[a, b, c],
        }),
        now: now,
      );
      expect(r.courses.map((x) => x.groupId).toSet().length, 3);
      expect(
        r.courses.firstWhere((x) => x.day == 3).externalKey,
        '线性代数|线性代数-07|3|5-6',
      );
    });

    test('其他学校：来源标记、课程 id 前缀都跟着学校 id 走', () {
      final other = ZfsoftAdapter(
        id: 'abc',
        name: 'ABC 大学',
        baseUrl: 'https://jw.abc.edu.cn/jwglxt',
        homeUrl: 'https://jw.abc.edu.cn/',
      );
      final r = other.parse(_fixture('shu_kb_envelope.json'), now: now);
      expect(r.schoolId, 'abc');
      expect(r.sourceTag, 'zfsoft-abc');
      expect(r.courses.every((c) => c.source == 'zfsoft-abc'), isTrue);
      expect(r.courses.every((c) => c.id.startsWith('zfsoft-abc-')), isTrue);
      expect(r.unscheduled.every((c) => c.source == 'zfsoft-abc'), isTrue);
    });

    test('上大的课程 id 与 1.2.0 完全一致（覆盖导入不会换 id）', () {
      final r = adapter.parse(_fixture('shu_kb_envelope.json'), now: now);
      expect(r.courses.every((c) => c.id.startsWith('zfsoft-shu-kb-')), isTrue);
    });

    test('allowedHosts：登录判定与注入前的 host 检查都认列表里的每个 host', () {
      final multi = ZfsoftAdapter(
        id: 'm',
        name: 'M',
        baseUrl: 'https://jw.m.edu.cn/jwglxt',
        homeUrl: 'https://jw.m.edu.cn/',
        allowedHosts: <String>['jw.m.edu.cn', 'JW2.m.edu.cn'],
      );
      expect(multi.allowedHosts, <String>['jw.m.edu.cn', 'jw2.m.edu.cn']);
      expect(
        multi.isLoggedIn('https://jw2.m.edu.cn/jwglxt/xtgl/index.html'),
        isTrue,
      );
      expect(multi.isAllowedHost('https://JW2.m.edu.cn/any'), isTrue);
      expect(multi.isAllowedHost('https://sso.m.edu.cn/login'), isFalse);
      expect(multi.isAllowedHost('not a url'), isFalse);
      // 不给 allowedHosts 时就是 baseUrl 的 host（与 1.2.0 行为一致）。
      expect(adapter.allowedHosts, <String>['jwxt.shu.edu.cn']);
      expect(adapter.captureMode, CaptureMode.fetch);
      expect(adapter.userAgent, isNull);
      expect(adapter.presets, isNull);
    });

    test('脚本出错时带回原始响应样本（诊断用），并限制在 200KB 内', () {
      final script = adapter.scrapeScript;
      expect(script, contains("fail('kb', '__NOTJSON__', txt)"));
      expect(script, contains("fail('kb', '__LOGIN__', txt)"));
      expect(script, contains('substring(0, 204800)'));
    });
  });

  group('导入结果可以直接喂给模型层', () {
    test('课程能往返 JSON 且不丢字段', () {
      final result = adapter.parse(_fixture('shu_kb_envelope.json'), now: now);
      for (final c in result.courses) {
        final back = Course.fromJson(jsonDecode(jsonEncode(c.toJson())));
        expect(back.name, c.name);
        expect(back.day, c.day);
        expect(back.startPeriod, c.startPeriod);
        expect(back.endPeriod, c.endPeriod);
        expect(back.weeks, c.weeks);
        expect(back.colorIndex, c.colorIndex);
        expect(back.source, c.source);
      }
    });

    test('周次文本可以被 formatWeeksText 还原成可读文本', () {
      final result = adapter.parse(_fixture('shu_kb_envelope.json'), now: now);
      final physics = _byName(result.courses, '大学物理(一)');
      expect(ScheduleUtils.formatWeeksText(physics.weeks), '1-8,10-16周');
    });
  });
}

// ------------------------------------------------------------------ 测试辅助

/// 跑一段期望抛 [ImportException] 的代码，把异常取出来。
ImportException _catchImport(Object? Function() body) {
  try {
    body();
  } on ImportException catch (e) {
    return e;
  }
  throw StateError('期望抛出 ImportException，实际没有抛');
}

Map<String, dynamic> _data() {
  final envelope =
      jsonDecode(_fixture('shu_kb_envelope.json')) as Map<String, dynamic>;
  return Map<String, dynamic>.from(envelope['data'] as Map);
}

String _encode(Map<String, dynamic> data) =>
    jsonEncode(<String, dynamic>{'ok': true, 'stage': 'done', 'data': data});

String _withCurrentWeek(int week) {
  final data = _data()..['currentWeek'] = week;
  return _encode(data);
}

String _withoutCurrentWeek() {
  final data = _data()..remove('currentWeek');
  return _encode(data);
}
