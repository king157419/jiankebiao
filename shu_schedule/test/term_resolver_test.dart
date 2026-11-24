import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/core/term_resolver.dart';

/// v1.5.0（PLAN-1.5 D8）：导入时推开学日期——教务识别 → 学校校历 → 不知道。
///
/// 内置假日表里上海大学 2026-2027 秋：2026-09-14 开学、18 周（最后一天 2027-01-17）。
/// 学校清单（schools.json）里另有 2026-2027 春：2027-02-22 开学、18 周。
void main() {
  final bundled = HolidayPresets.fromJson(
    jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map,
  );

  final schoolsJsonPresets = <TermPreset>[
    TermPreset(
      id: 'shu-2026-autumn',
      name: '2026-2027 秋',
      startDate: DateTime(2026, 9, 14),
      totalWeeks: 18,
    ),
    TermPreset(
      id: 'shu-2027-spring',
      name: '2026-2027 春',
      startDate: DateTime(2027, 2, 22),
      totalWeeks: 18,
    ),
  ];

  group('HolidayPresets.termCovering', () {
    test('[startDate, startDate + totalWeeks * 7) 包含 today 才算', () {
      SchoolTerm? on(DateTime d) => bundled.termCovering('shu', d);
      expect(on(DateTime(2026, 9, 13)), isNull, reason: '开学前一天');
      expect(on(DateTime(2026, 9, 14))?.startDate, DateTime(2026, 9, 14));
      expect(on(DateTime(2026, 10, 8))?.name, '2026-2027 学年秋季学期');
      expect(on(DateTime(2027, 1, 17)), isNotNull, reason: '第 18 周周日');
      expect(on(DateTime(2027, 1, 18)), isNull, reason: '学期结束后一天');
      expect(bundled.termCovering('nope', DateTime(2026, 10, 8)), isNull);
      expect(
        HolidayPresets.empty.termCovering('shu', DateTime(2026, 10, 8)),
        isNull,
      );
    });
  });

  group('schoolCalendarTerms', () {
    test('假日表 ∪ 学校清单：同一开学日期只留假日表那条，按日期排序', () {
      final terms = schoolCalendarTerms(
        schoolId: 'shu',
        presets: bundled,
        schoolPresets: schoolsJsonPresets.reversed.toList(),
      );
      expect(terms.map((t) => t.startDate).toList(), <DateTime>[
        DateTime(2026, 9, 14),
        DateTime(2027, 2, 22),
      ]);
      expect(terms.first.name, '2026-2027 学年秋季学期');
      expect(terms.first.fromHolidays, isTrue);
      expect(terms.last.name, '2026-2027 春');
      expect(terms.last.fromHolidays, isFalse);
    });

    test('学校清单里的开学日期不是周一 → 对齐到周一后再去重', () {
      final terms = schoolCalendarTerms(
        schoolId: 'shu',
        presets: bundled,
        schoolPresets: <TermPreset>[
          TermPreset(
            id: 'x',
            name: '周三开学写法',
            startDate: DateTime(2026, 9, 16),
            totalWeeks: 18,
          ),
        ],
      );
      expect(terms, hasLength(1));
      expect(terms.single.fromHolidays, isTrue);
    });

    test('没有 schoolId / 这所学校没有校历 → 空', () {
      expect(
        schoolCalendarTerms(
          schoolId: null,
          presets: bundled,
          schoolPresets: schoolsJsonPresets,
        ),
        isEmpty,
      );
      expect(schoolCalendarTerms(schoolId: 'nope', presets: bundled), isEmpty);
    });
  });

  group('schoolTermCovering', () {
    test('两边都覆盖今天时假日表优先', () {
      final term = schoolTermCovering(
        schoolId: 'shu',
        presets: bundled,
        schoolPresets: <TermPreset>[
          TermPreset(
            id: 'other',
            name: '学校清单里另一种写法',
            startDate: DateTime(2026, 9, 7),
            totalWeeks: 20,
          ),
        ],
        today: DateTime(2026, 10, 8),
      );
      expect(term?.startDate, DateTime(2026, 9, 14));
      expect(term?.fromHolidays, isTrue);
    });

    test('假日表没有、学校清单有（下学期）→ 用学校清单的', () {
      final term = schoolTermCovering(
        schoolId: 'shu',
        presets: bundled,
        schoolPresets: schoolsJsonPresets,
        today: DateTime(2027, 3, 1),
      );
      expect(term?.name, '2026-2027 春');
      expect(term?.startDate, DateTime(2027, 2, 22));
      expect(term?.fromHolidays, isFalse);
    });

    test('寒假（两学期之间）→ null', () {
      expect(
        schoolTermCovering(
          schoolId: 'shu',
          presets: bundled,
          schoolPresets: schoolsJsonPresets,
          today: DateTime(2027, 2, 1),
        ),
        isNull,
      );
    });
  });

  group('resolveTermStart', () {
    test('教务识别到周次 → detected（对齐周一），即使校历也有', () {
      final r = resolveTermStart(
        detectedStart: DateTime(2026, 9, 16),
        detectedWeek: 3,
        schoolId: 'shu',
        presets: bundled,
        schoolName: '上海大学',
        today: DateTime(2026, 10, 8),
      );
      expect(r.source, TermStartSource.detected);
      expect(r.startDate, DateTime(2026, 9, 14));
      expect(r.currentWeek, 3, reason: '文案用教务页面上的周次');
      expect(r.totalWeeks, isNull);
      expect(r.label, '教务系统显示当前第 3 周');
    });

    test('教务只给了开学日期没给周次 → 按今天算周次', () {
      final r = resolveTermStart(
        detectedStart: DateTime(2026, 9, 14),
        presets: HolidayPresets.empty,
        today: DateTime(2026, 10, 8),
      );
      expect(r.source, TermStartSource.detected);
      expect(r.currentWeek, 4);
    });

    test('没识别到 + 校历覆盖今天 → schoolCalendar：9月14日开学、18 周、现在第 4 周', () {
      final r = resolveTermStart(
        schoolId: 'shu',
        presets: bundled,
        schoolPresets: schoolsJsonPresets,
        schoolName: '学校清单里的名字',
        today: DateTime(2026, 10, 8),
      );
      expect(r.source, TermStartSource.schoolCalendar);
      expect(r.startDate, DateTime(2026, 9, 14));
      expect(r.totalWeeks, 18);
      expect(r.termName, '2026-2027 学年秋季学期');
      expect(r.schoolName, '上海大学', reason: '假日表里的校名优先');
      expect(r.currentWeek, 4);
      expect(r.label, '按上海大学校历 · 9月14日开学 · 现在第 4 周');
    });

    test(
      '边界与开学前 28 天窗口：开学前 28 天内 → schoolCalendar+upcoming；更早或结束后无新学期 → unknown',
      () {
        TermResolution on(DateTime d) =>
            resolveTermStart(schoolId: 'shu', presets: bundled, today: d);
        // 开学当天与第 18 周周日：学期内。
        final first = on(DateTime(2026, 9, 14));
        expect(first.source, TermStartSource.schoolCalendar);
        expect(first.upcoming, isFalse);
        expect(first.currentWeek, 1);
        final last = on(DateTime(2027, 1, 17));
        expect(last.source, TermStartSource.schoolCalendar);
        expect(last.upcoming, isFalse);
        expect(last.currentWeek, 18);

        // 开学前 28 天内（9/10、9/13、边界 8/17）：schoolCalendar + upcoming。
        for (final pre in <DateTime>[
          DateTime(2026, 9, 10),
          DateTime(2026, 9, 13),
          DateTime(2026, 8, 17),
        ]) {
          final r = on(pre);
          expect(r.source, TermStartSource.schoolCalendar, reason: '$pre');
          expect(r.upcoming, isTrue, reason: '$pre');
          expect(r.startDate, DateTime(2026, 9, 14), reason: '$pre');
          expect(r.totalWeeks, 18, reason: '$pre');
          expect(r.label, '按上海大学校历 · 9月14日开学 · 还没开学', reason: '$pre');
        }

        // 超过 28 天（8/1、8/16）或 1/18 之后（bundled 无下学期）→ unknown。
        expect(on(DateTime(2026, 8, 1)).source, TermStartSource.unknown);
        expect(on(DateTime(2026, 8, 16)).source, TermStartSource.unknown);
        expect(on(DateTime(2027, 1, 18)).source, TermStartSource.unknown);
      },
    );

    test('只有学校清单的学期 → 也算校历（含寒假末尾 28 天内即将开学），校名用传进来的', () {
      final r = resolveTermStart(
        schoolId: 'shu',
        presets: HolidayPresets.empty,
        schoolPresets: schoolsJsonPresets,
        schoolName: '某某大学',
        today: DateTime(2027, 3, 3),
      );
      expect(r.source, TermStartSource.schoolCalendar);
      expect(r.upcoming, isFalse);
      expect(r.startDate, DateTime(2027, 2, 22));
      expect(r.currentWeek, 2);
      expect(r.label, '按某某大学校历 · 2月22日开学 · 现在第 2 周');

      // 2027-02-01 距 2/22 还有 21 天（<= 28）→ upcoming。
      final preSpring = resolveTermStart(
        schoolId: 'shu',
        presets: bundled,
        schoolPresets: schoolsJsonPresets,
        today: DateTime(2027, 2, 1),
      );
      expect(preSpring.source, TermStartSource.schoolCalendar);
      expect(preSpring.upcoming, isTrue);
      expect(preSpring.startDate, DateTime(2027, 2, 22));
      expect(preSpring.label, '按上海大学校历 · 2月22日开学 · 还没开学');
    });

    test('都没有（含两学期之间距下学期 > 28 天）→ unknown：没有开学日期，不再默认「今天是第一周」', () {
      for (final r in <TermResolution>[
        resolveTermStart(presets: bundled, today: DateTime(2026, 10, 8)),
        resolveTermStart(
          schoolId: 'nope',
          presets: bundled,
          today: DateTime(2026, 10, 8),
        ),
        resolveTermStart(
          schoolId: 'shu',
          presets: bundled,
          schoolPresets: schoolsJsonPresets,
          today: DateTime(2027, 1, 20),
        ),
      ]) {
        expect(r.source, TermStartSource.unknown);
        expect(r.startDate, isNull);
        expect(r.currentWeek, isNull);
        expect(r.label, '还没确定 · 点这里选');
      }
    });
  });

  group('weekNumberOn / monthDayText', () {
    test('和 rawWeekOf 一致：开学前是 0 或负数', () {
      final start = DateTime(2026, 9, 14);
      expect(weekNumberOn(start, DateTime(2026, 9, 14)), 1);
      expect(weekNumberOn(start, DateTime(2026, 9, 20)), 1);
      expect(weekNumberOn(start, DateTime(2026, 9, 21)), 2);
      expect(weekNumberOn(start, DateTime(2026, 10, 8)), 4);
      expect(weekNumberOn(start, DateTime(2026, 9, 13)), 0);
      expect(weekNumberOn(start, DateTime(2026, 9, 6)), -1);
      // 夏令时附近（开发机所在时区 11 月初切换）也按日历算。
      expect(weekNumberOn(start, DateTime(2026, 11, 2)), 8);
      expect(
        weekNumberOn(DateTime(2026, 9, 16), DateTime(2026, 9, 21)),
        2,
        reason: '开学日期先对齐到周一',
      );
      expect(ScheduleUtils.mondayOf(DateTime(2026, 11, 1)).hour, 0);
    });

    test('「9月14日」', () {
      expect(monthDayText(DateTime(2026, 9, 14)), '9月14日');
      expect(monthDayText(DateTime(2027, 2, 22)), '2月22日');
    });
  });
}
