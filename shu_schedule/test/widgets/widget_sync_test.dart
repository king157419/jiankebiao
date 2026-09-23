import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/features/widgets/demo_timetable.dart';
import 'package:shu_schedule/features/widgets/widget_sync.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

void main() {
  // 2026-09-16 是 SHU 2026 秋第 1 周的周三。
  final now = DateTime(2026, 9, 16, 10, 30);
  final palette = WidgetPalette.fallback();

  group('WidgetPalette', () {
    test('hex 输出 #RRGGBB 且丢掉 alpha', () {
      expect(WidgetPalette.hex(const Color(0xFF933E6A)), '#933E6A');
      expect(WidgetPalette.hex(const Color(0x80FFFFFF)), '#FFFFFF');
      expect(WidgetPalette.hex(const Color(0xFF000000)), '#000000');
    });

    test('fallback 有 10 个课程色', () {
      expect(palette.courseColors.length, 10);
    });

    test('courseColor 对越界索引取模而不是抛异常', () {
      expect(palette.courseColor(12), palette.courseColors[2]);
      expect(palette.courseColor(-1), palette.courseColors[9]);
    });

    test('normalizeCourseColors 补齐到 10 个', () {
      final list = WidgetPalette.normalizeCourseColors(<Color>[
        const Color(0xFF111111),
        const Color(0xFF222222),
      ]);
      expect(list.length, 10);
      expect(list[0], const Color(0xFF111111));
      expect(list[3], const Color(0xFF222222));
    });
  });

  group('WidgetSync.buildSnapshot', () {
    // v1.3.0：从 14 天扩到整学期 min(totalWeeks*7+7, 150)；示例课表 18 周 → 133 天。
    test('覆盖整学期（133 天）、日期连续、weekday 正确', () {
      final snapshot = WidgetSync.buildSnapshot(
        buildDemoTimetable(),
        palette,
        now: now,
      );
      final days = snapshot['days'] as List<dynamic>;
      expect(days.length, 133);
      expect(WidgetSync.snapshotDaysFor(buildDemoTimetable().config), 133);
      expect((days.first as Map)['date'], '2026-09-16');
      expect((days.first as Map)['weekday'], 3);
      expect((days[13] as Map)['date'], '2026-09-29');
      expect((days[13] as Map)['week'], 3);
      // 2026-09-16 + 132 天 = 2027-01-26（跨年、跨月都靠 addDays，不能漂移）。
      expect((days.last as Map)['date'], '2027-01-26');
      expect((days.last as Map)['weekday'], 2);
      expect((days.last as Map)['week'], isNull, reason: '学期已结束');
      for (var i = 1; i < days.length; i++) {
        final prev = DateTime.parse((days[i - 1] as Map)['date'] as String);
        final cur = DateTime.parse((days[i] as Map)['date'] as String);
        expect(ScheduleUtils.daysBetween(prev, cur), 1, reason: '第 $i 天');
      }
    });

    test('今天的课按开始节次排序并带完整时间', () {
      final snapshot = WidgetSync.buildSnapshot(
        buildDemoTimetable(),
        palette,
        now: now,
      );
      final today = (snapshot['days'] as List<dynamic>).first as Map;
      final courses = (today['courses'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(courses.length, 2);
      expect(courses[0]['name'], '线性代数');
      expect(courses[0]['start'], '08:00');
      expect(courses[0]['end'], '09:40');
      expect(courses[1]['name'], '数据结构');
      expect(courses[1]['start'], '13:00');
      expect(courses[1]['end'], '14:40');
      expect(courses[0]['color'], startsWith('#'));
    });

    test('单周课在双周那天不出现', () {
      final snapshot = WidgetSync.buildSnapshot(
        buildDemoTimetable(),
        palette,
        now: now,
      );
      // 下周三 = 2026-09-23，第 2 周（双），线性代数只在单周。
      final nextWed = (snapshot['days'] as List<dynamic>).firstWhere(
        (d) => (d as Map)['date'] == '2026-09-23',
      ) as Map;
      expect(nextWed['week'], 2);
      final names = (nextWed['courses'] as List<dynamic>)
          .map((c) => (c as Map)['name'])
          .toList();
      expect(names, isNot(contains('线性代数')));
      expect(names, contains('数据结构'));
    });

    test('学期外的日期 week = null 且无课（假期）', () {
      final timetable = buildDemoTimetable();
      // 开学前一周。
      final snapshot = WidgetSync.buildSnapshot(
        timetable,
        palette,
        now: DateTime(2026, 9, 1),
      );
      final first = (snapshot['days'] as List<dynamic>).first as Map;
      expect(first['week'], isNull);
      expect(first['courses'], isEmpty);
    });

    test('palette 与 periods 一并写进快照', () {
      final snapshot = WidgetSync.buildSnapshot(
        buildDemoTimetable(),
        palette,
        now: now,
      );
      final p = snapshot['palette'] as Map<String, dynamic>;
      expect(p['surface'], '#FFFFFF');
      expect(p['isDark'], false);
      expect((p['courseColors'] as List<dynamic>).length, 10);
      expect((snapshot['periods'] as List<dynamic>).length, 12);
      expect(snapshot['timetableName'], '示例课表');
    });

    test('buildSnapshotJson 是合法 JSON 且可往返', () {
      final json = WidgetSync.buildSnapshotJson(
        buildDemoTimetable(),
        palette,
        now: now,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['version'], WidgetSync.snapshotVersion);
      expect((decoded['days'] as List<dynamic>).length, 133);
    });

    test('空课表不崩溃', () {
      final empty = Timetable(
        id: 'empty',
        name: '空课表',
        config: ScheduleConfig.defaults(),
      );
      final snapshot = WidgetSync.buildSnapshot(empty, palette, now: now);
      final days = (snapshot['days'] as List<dynamic>).cast<Map>();
      expect(days.length, 133);
      expect(days.every((d) => (d['courses'] as List).isEmpty), isTrue);
    });

    // 小组件最远能翻到今天 +6；它只认快照，翻页时不会拉起 Flutter，
    // 所以快照必须自带这一整个窗口的天数。
    test('翻页窗口（今天起 7 天）齐全，日期连续且 week 跨周递增', () {
      final snapshot = WidgetSync.buildSnapshot(
        buildDemoTimetable(),
        palette,
        now: now,
      );
      final days = (snapshot['days'] as List<dynamic>).cast<Map>();
      expect(days.length, greaterThanOrEqualTo(7));

      final window = days.take(7).toList();
      // 2026-09-16 是周三第 1 周；周日（09-20）之后跨到第 2 周。
      expect(window.map((d) => d['date']).toList(), <String>[
        '2026-09-16',
        '2026-09-17',
        '2026-09-18',
        '2026-09-19',
        '2026-09-20',
        '2026-09-21',
        '2026-09-22',
      ]);
      expect(window.map((d) => d['weekday']).toList(), <int>[
        3,
        4,
        5,
        6,
        7,
        1,
        2,
      ]);
      expect(window.map((d) => d['week']).toList(), <int>[1, 1, 1, 1, 1, 2, 2]);
    });

    test('窗口尾部越过学期末时是空的一天而不是崩溃', () {
      final timetable = buildDemoTimetable();
      final config = timetable.config;
      // 最后一周的周四：往后翻 6 天必然越过学期末。
      final lastThursday = ScheduleUtils.addDays(
        config.startDate,
        (config.totalWeeks - 1) * 7 + 3,
      );
      final snapshot = WidgetSync.buildSnapshot(
        timetable,
        palette,
        now: lastThursday,
      );
      final days = (snapshot['days'] as List<dynamic>).cast<Map>();

      expect(days.first['week'], config.totalWeeks);
      // 学期末之后的那几天：week = null、无课，而不是抛异常或越界周数。
      final afterTerm = days.where((d) => d['week'] == null).toList();
      expect(afterTerm, isNotEmpty);
      expect(afterTerm.every((d) => (d['courses'] as List).isEmpty), isTrue);
      expect(
        days.every(
          (d) => d['week'] == null || d['week'] as int <= config.totalWeeks,
        ),
        isTrue,
      );
    });

    // v1.2.0 起只剩一个小组件，refreshTargets 里多写一个已经不存在的 Provider
    // 会让每次 push 都吞一个异常，少写则小组件收不到刷新。
    test('refreshTargets 只有唯一那个 Provider', () {
      expect(WidgetSync.refreshTargets, <String>[
        WidgetSync.dayProviderQualified,
      ]);
      expect(
        WidgetSync.dayProviderQualified,
        'cn.shu.schedule.widgets.DayWidgetProvider',
      );
    });

    test('节次越界的脏数据会被裁剪而不是抛异常', () {
      final timetable = Timetable(
        id: 'dirty',
        name: '脏数据',
        config: ScheduleConfig(
          name: 'x',
          startDate: DateTime(2026, 9, 14),
          totalWeeks: 18,
          periods: List.of(defaultPeriods),
        ),
        courses: <Course>[
          Course(
            id: 'x1',
            name: '越界课',
            day: 3,
            startPeriod: 99,
            endPeriod: 120,
            weeks: <int>[1],
            colorIndex: 42,
          ),
        ],
      );
      final snapshot = WidgetSync.buildSnapshot(timetable, palette, now: now);
      final today = (snapshot['days'] as List<dynamic>).first as Map;
      final course = (today['courses'] as List<dynamic>).first as Map;
      expect(course['start'], '20:55');
      expect(course['end'], '21:40');
      expect(course['color'], startsWith('#'));
    });
  });
}
