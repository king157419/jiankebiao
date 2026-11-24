import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/models/schedule_config.dart';

/// v1.3.1：内置节假日数据（`assets/holidays.json`）→ 套用建议。
void main() {
  late HolidayPresets presets;

  setUpAll(() {
    final text = File('assets/holidays.json').readAsStringSync();
    presets = HolidayPresets.fromJson(jsonDecode(text) as Map);
  });

  ScheduleConfig term(
    DateTime start, {
    int weeks = 18,
    Map<String, DateOverride>? overrides,
  }) => ScheduleConfig(
    name: '学期',
    startDate: start,
    totalWeeks: weeks,
    overrides: overrides,
  );

  HolidaySuggestion at(List<HolidaySuggestion> items, String key) =>
      items.singleWhere((s) => ScheduleUtils.dateKey(s.date) == key);

  bool has(List<HolidaySuggestion> items, String key) =>
      items.any((s) => ScheduleUtils.dateKey(s.date) == key);

  group('资源文件', () {
    test('已登记进 pubspec：rootBundle 能读到（loadBundled）', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bundled = await HolidayPresets.loadBundled();
      expect(bundled.schools['shu']?.terms.single.entries, hasLength(13));
      expect(bundled.national.keys, contains(2026));
    });

    test('能解析出 2026 国家安排和上大秋季学期', () {
      expect(presets.national.keys, contains(2026));
      expect(presets.national[2026]!.holidays, hasLength(7));
      expect(
        presets.national[2026]!.sourceUrl,
        startsWith('https://www.gov.cn/'),
      );
      final shu = presets.schools['shu']!;
      expect(shu.name, '上海大学');
      expect(shu.terms.single.entries, hasLength(13));
      expect(shu.terms.single.startDate, DateTime(2026, 9, 14));
    });
  });

  group('学校通知（上大 2026 秋）', () {
    final config = term(DateTime(2026, 9, 14));

    test('13 条，全部来自学校，按日期排序', () {
      final plan = presets.planFor(config: config, schoolId: 'shu');
      expect(plan.title, '上海大学 · 2026-2027 学年秋季学期');
      expect(plan.sourceUrl, 'https://www.shu.edu.cn/info/1051/400395.htm');
      expect(plan.sourceText, contains('上海大学党政办公室'));
      final items = plan.items;
      expect(items, hasLength(13));
      expect(items.every((s) => s.fromSchool), isTrue);
      expect(items.every((s) => !s.needsConfirmation), isTrue);
      expect(items.every((s) => s.warning == null), isTrue);
      final dates = items.map((s) => s.date).toList();
      expect(dates, orderedEquals(List<DateTime>.from(dates)..sort()));
      expect(ScheduleUtils.dateKey(items.first.date), '2026-09-20');
      expect(ScheduleUtils.dateKey(items.last.date), '2027-01-01');
    });

    test('9/20 上第 4 周周二（10/6）的课，10/10 上第 4 周周三（10/7）的课', () {
      final items = presets.suggestionsFor(config: config, schoolId: 'shu');
      final sep20 = at(items, '2026-09-20').override!;
      expect(sep20.cancelled, isFalse);
      expect(sep20.actAsWeek, 4);
      expect(sep20.actAsWeekday, 2);
      expect(sep20.note, contains('10 月 6 日'));
      final oct10 = at(items, '2026-10-10').override!;
      expect(oct10.actAsWeek, 4);
      expect(oct10.actAsWeekday, 3);
    });

    test('10/1 停课（带学校备注）', () {
      final items = presets.suggestionsFor(config: config, schoolId: 'shu');
      expect(
        at(items, '2026-10-01').override,
        const DateOverride.cancelled(note: '国庆节放假'),
      );
      expect(at(items, '2026-09-25').override!.cancelled, isTrue);
    });

    test('开学日期不同但学期范围重叠时仍用学校数据；被调换的日子跑出学期时带 warning', () {
      // 开学晚 4 周：10/6 落在第 0 周 → 学期外。
      final later = term(DateTime(2026, 10, 12));
      final items = presets.suggestionsFor(config: later, schoolId: 'shu');
      expect(items, isNotEmpty);
      expect(items.every((s) => s.fromSchool), isTrue);
      // 9/20、10/1 都在新学期之前，不返回。
      expect(has(items, '2026-09-20'), isFalse);
      expect(has(items, '2026-10-01'), isFalse);
      expect(has(items, '2027-01-01'), isTrue);

      final early = term(DateTime(2026, 9, 7), weeks: 2); // 9/7 ~ 9/20
      final e = presets.suggestionsFor(config: early, schoolId: 'shu');
      final sep20 = at(e, '2026-09-20');
      expect(sep20.override!.actAsWeek, 5); // 10/6 是这个学期的第 5 周
      expect(sep20.warning, isNotNull);
    });

    test('学校没有对得上的学期 → 退回国家安排', () {
      final spring = term(DateTime(2026, 2, 23));
      final plan = presets.planFor(config: spring, schoolId: 'shu');
      expect(plan.title, '国家法定节假日（2026）');
      expect(plan.items.every((s) => !s.fromSchool), isTrue);
    });
  });

  group('国家安排', () {
    test('未知学校的 2026 秋：10 天停课 + 9/20、10/10 需要确认，学期外日期不出现', () {
      final config = term(DateTime(2026, 9, 14));
      for (final schoolId in <String?>[null, 'unknown-school']) {
        final plan = presets.planFor(config: config, schoolId: schoolId);
        expect(plan.title, '国家法定节假日（2026）');
        expect(plan.sourceUrl, contains('gov.cn'));
        final items = plan.items;
        final cancelled = items.where((s) => s.override?.cancelled ?? false);
        expect(cancelled.map((s) => ScheduleUtils.dateKey(s.date)), <String>[
          '2026-09-25',
          '2026-09-26',
          '2026-09-27',
          '2026-10-01',
          '2026-10-02',
          '2026-10-03',
          '2026-10-04',
          '2026-10-05',
          '2026-10-06',
          '2026-10-07',
        ]);
        expect(
          at(items, '2026-10-01').override,
          const DateOverride.cancelled(note: '国庆节放假（国家安排）'),
        );
        for (final key in <String>['2026-09-20', '2026-10-10']) {
          final s = at(items, key);
          expect(s.needsConfirmation, isTrue);
          expect(s.override, isNull);
          expect(s.applicable, isFalse);
          expect(s.note, contains('国家调休上班'));
        }
        expect(at(items, '2026-09-20').note, startsWith('9月20日（周日）'));
        expect(items, hasLength(12));
        expect(has(items, '2026-06-19'), isFalse);
        expect(has(items, '2026-01-01'), isFalse);
        expect(items.every((s) => !s.fromSchool), isTrue);
      }
    });

    test('2026 春（2/23 开学 18 周）：清明 / 劳动节 / 端午 + 5/9 需要确认', () {
      final config = term(DateTime(2026, 2, 23));
      final items = presets.suggestionsFor(config: config);
      for (final key in <String>[
        '2026-02-23', // 春节最后一天
        '2026-04-04',
        '2026-04-05',
        '2026-04-06',
        '2026-05-01',
        '2026-05-05',
        '2026-06-19',
        '2026-06-21',
      ]) {
        expect(at(items, key).override?.cancelled, isTrue, reason: key);
      }
      expect(at(items, '2026-04-05').override!.note, '清明节放假（国家安排）');
      expect(at(items, '2026-05-09').needsConfirmation, isTrue);
      expect(at(items, '2026-02-28').needsConfirmation, isTrue);
      // 学期外：春节前的调休、国庆。
      expect(has(items, '2026-02-14'), isFalse);
      expect(has(items, '2026-02-22'), isFalse);
      expect(has(items, '2026-10-01'), isFalse);
    });

    test('没有数据的年份 → 空方案', () {
      final plan = presets.planFor(config: term(DateTime(2030, 9, 2)));
      expect(plan.isEmpty, isTrue);
    });
  });

  group('已有设置', () {
    test('完全相同 → alreadyApplied；不同 → conflicts', () {
      final config = term(
        DateTime(2026, 9, 14),
        overrides: <String, DateOverride>{
          '2026-10-01': const DateOverride.cancelled(note: '国庆节放假'),
          '2026-10-02': const DateOverride.cancelled(note: '运动会'),
          '2026-11-11': const DateOverride.cancelled(note: '与节假日无关'),
        },
      );
      final items = presets.suggestionsFor(config: config, schoolId: 'shu');
      final same = at(items, '2026-10-01');
      expect(same.alreadyApplied, isTrue);
      expect(same.conflicts, isFalse);
      expect(same.applicable, isFalse);
      final diff = at(items, '2026-10-02');
      expect(diff.conflicts, isTrue);
      expect(diff.alreadyApplied, isFalse);
      expect(diff.existing, const DateOverride.cancelled(note: '运动会'));
      expect(at(items, '2026-10-03').existing, isNull);
      expect(has(items, '2026-11-11'), isFalse);
    });
  });

  group('容错解析', () {
    test('坏条目丢掉，不抛异常', () {
      final p = HolidayPresets.fromJson(<String, dynamic>{
        'national': <String, dynamic>{
          '2026': <String, dynamic>{
            'holidays': <dynamic>[
              <String, dynamic>{
                'name': '国庆节',
                'off': <dynamic>['2026-10-01', 'not-a-date', 42, null],
                'work': 'oops',
              },
              <String, dynamic>{
                'off': <dynamic>['2026-10-02'],
              }, // 没名字
              'garbage',
            ],
          },
          'abc': <String, dynamic>{'holidays': <dynamic>[]},
          '2027': 'not a map',
        },
        'schools': <String, dynamic>{
          'x': <String, dynamic>{
            'name': '某大学',
            'terms': <dynamic>[
              <String, dynamic>{
                'name': '秋',
                'startDate': '2026-09-14',
                'totalWeeks': 18,
                'entries': <dynamic>[
                  <String, dynamic>{'date': '2026-10-01', 'cancelled': true},
                  <String, dynamic>{'date': 'bad', 'cancelled': true},
                  <String, dynamic>{'date': '2026-10-02'}, // 既不停课也没 actAsDate
                  <String, dynamic>{'date': '2026-10-03', 'actAsDate': 'x'},
                  <String, dynamic>{'date': '2026-10-01', 'cancelled': true},
                  7,
                ],
              },
              <String, dynamic>{'name': '缺开学日期', 'totalWeeks': 18},
              <String, dynamic>{'startDate': '2026-02-23', 'totalWeeks': 'x'},
            ],
          },
          'y': 'not a map',
          'z': <String, dynamic>{'name': '没有 terms'},
        },
      });
      expect(p.national.keys, <int>[2026]);
      final h = p.national[2026]!.holidays.single;
      expect(h.off, <DateTime>[DateTime(2026, 10, 1)]);
      expect(h.work, isEmpty);
      expect(p.schools.keys, <String>['x']);
      final t = p.schools['x']!.terms.single;
      expect(t.entries, hasLength(1));
      final items = p.suggestionsFor(
        config: term(DateTime(2026, 9, 14)),
        schoolId: 'x',
      );
      expect(items.single.override, const DateOverride.cancelled());
    });

    test('完全不像样的输入 → 空', () {
      final p = HolidayPresets.fromJson(<String, dynamic>{
        'national': <dynamic>[],
        'schools': 3,
      });
      expect(p.national, isEmpty);
      expect(p.schools, isEmpty);
      expect(p.suggestionsFor(config: term(DateTime(2026, 9, 14))), isEmpty);
    });
  });
}
