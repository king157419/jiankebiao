import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/features/widgets/demo_timetable.dart';
import 'package:shu_schedule/features/widgets/widget_sync.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

/// v1.3.0 Phase A：小组件快照覆盖整学期 + 调休 / 停课展开。
void main() {
  final palette = WidgetPalette.fallback();

  Map<String, dynamic> dayOf(Map<String, dynamic> snapshot, String date) =>
      (snapshot['days'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((d) => d['date'] == date);

  List<String> namesOf(Map<String, dynamic> day) => (day['courses'] as List)
      .map((c) => (c as Map)['name'] as String)
      .toList();

  group('snapshotDaysFor', () {
    ScheduleConfig cfg(int weeks) => ScheduleConfig(
      name: 'x',
      startDate: DateTime(2026, 9, 14),
      totalWeeks: weeks,
    );

    test('= min(totalWeeks * 7 + 7, 150)', () {
      expect(WidgetSync.snapshotDaysFor(cfg(1)), 14);
      expect(WidgetSync.snapshotDaysFor(cfg(16)), 119);
      expect(WidgetSync.snapshotDaysFor(cfg(18)), 133);
      expect(WidgetSync.snapshotDaysFor(cfg(20)), 147);
      expect(WidgetSync.snapshotDaysFor(cfg(21)), 150);
      expect(WidgetSync.snapshotDaysFor(cfg(60)), 150);
      expect(WidgetSync.maxSnapshotDays, 150);
    });

    test('学期中任何一天打开 App，快照都覆盖到学期最后一天 + 6 天翻页', () {
      final tt = buildDemoTimetable();
      final config = tt.config;
      final lastDay = ScheduleUtils.dateOf(config, config.totalWeeks, 7);
      for (var week = 1; week <= config.totalWeeks; week++) {
        final now = ScheduleUtils.dateOf(config, week, 1);
        final days =
            (WidgetSync.buildSnapshot(tt, palette, now: now)['days'] as List)
                .cast<Map>();
        final covered = days.map((d) => d['date']).toSet();
        for (var extra = 0; extra <= 6; extra++) {
          final key = ScheduleUtils.dateKey(
            ScheduleUtils.addDays(lastDay, extra),
          );
          expect(covered, contains(key), reason: '第 $week 周打开，缺 $key');
        }
      }
    });
  });

  group('调休 / 停课在快照里展开', () {
    // 示例课表：周一 高数(1-2)，周二 英语(3-4)，周三 线代(单周 1-2) + 数据结构(5-6)，
    // 周四 物理(3-4)，周五 体育(7-8)。开学 2026-09-14（周一）。
    final now = DateTime(2026, 9, 28, 7); // 第 3 周周一

    test('停课日没有课，并带「停课」标签', () {
      final tt = buildDemoTimetable();
      tt.config = tt.config.withOverride(
        DateTime(2026, 10, 1),
        const DateOverride.cancelled(note: '国庆节'),
      );
      final snapshot = WidgetSync.buildSnapshot(tt, palette, now: now);
      final oct1 = dayOf(snapshot, '2026-10-01'); // 周四，原本有大学物理
      expect(oct1['courses'], isEmpty);
      expect(oct1['label'], '停课');
      expect(oct1['note'], '国庆节');
      expect(oct1['week'], 3, reason: '日历周次不变');
      // 没有调休的日子不带 label 字段（旧的原生端也不受影响）。
      expect(dayOf(snapshot, '2026-09-29').containsKey('label'), isFalse);
    });

    test('国庆后周六按周一上课', () {
      final tt = buildDemoTimetable();
      tt.config = tt.config.withOverride(
        DateTime(2026, 10, 10), // 第 4 周周六
        const DateOverride.actAs(weekday: 1, note: '补 10 月 5 日（周一）的课'),
      );
      final snapshot = WidgetSync.buildSnapshot(tt, palette, now: now);
      final sat = dayOf(snapshot, '2026-10-10');
      expect(sat['weekday'], 6, reason: '日历上还是周六');
      expect(sat['week'], 4);
      expect(namesOf(sat), <String>['高等数学 A(一)']);
      expect(sat['label'], '调休');
      expect(sat['note'], '补 10 月 5 日（周一）的课');
    });

    test('指定周次：按第 1 周上课（单周课出现在双周的日子里）', () {
      final tt = buildDemoTimetable();
      // 2026-10-14 是第 5 周（单周）周三；改成按第 2 周（双周）上 → 线代不上。
      tt.config = tt.config.withOverride(
        DateTime(2026, 10, 14),
        const DateOverride.actAs(week: 2),
      );
      // 2026-10-21 是第 6 周（双周）周三；改成按第 1 周（单周）上 → 线代要上。
      tt.config = tt.config.withOverride(
        DateTime(2026, 10, 21),
        const DateOverride.actAs(week: 1),
      );
      final snapshot = WidgetSync.buildSnapshot(tt, palette, now: now);
      expect(namesOf(dayOf(snapshot, '2026-10-14')), <String>['数据结构']);
      expect(namesOf(dayOf(snapshot, '2026-10-21')), <String>['线性代数', '数据结构']);
      expect(dayOf(snapshot, '2026-10-21')['note'], '调休，按第 1 周周三上课');
    });

    test('快照与 ScheduleUtils.coursesOn 逐日一致（同一个入口）', () {
      final tt = buildDemoTimetable();
      tt.config = tt.config
          .withOverride(DateTime(2026, 10, 1), const DateOverride.cancelled())
          .withOverride(
            DateTime(2026, 10, 10),
            const DateOverride.actAs(weekday: 4),
          )
          .withOverride(
            DateTime(2026, 11, 4),
            const DateOverride.actAs(week: 2, weekday: 3),
          );
      final snapshot = WidgetSync.buildSnapshot(tt, palette, now: now);
      for (final day
          in (snapshot['days'] as List).cast<Map<String, dynamic>>()) {
        final date = DateTime.parse(day['date'] as String);
        final expected = ScheduleUtils.isDuringTerm(date, tt.config)
            ? ScheduleUtils.coursesOn(date, tt).map((c) => c.name).toList()
            : <String>[];
        expect(namesOf(day), expected, reason: day['date'] as String);
      }
    });
  });

  group('快照体积', () {
    test('150 天满课（每天 12 节都有课、长课程名）的 JSON < 500KB', () {
      final allWeeks = <int>[for (var w = 1; w <= 30; w++) w];
      final courses = <Course>[
        for (var d = 1; d <= 7; d++)
          for (var p = 1; p <= 12; p++)
            Course(
              id: 'c-$d-$p',
              name: '大学英语综合课程与跨文化交际（第$p讲）',
              teacher: '欧阳某某老师',
              location: '宝山校区东区教学楼 J-${100 + p}',
              day: d,
              startPeriod: p,
              endPeriod: p,
              weeks: allWeeks,
              colorIndex: p % 10,
              source: 'zfsoft-shu',
            ),
      ];
      final tt = Timetable(
        id: 'full',
        name: '满课压力测试课表',
        config: ScheduleConfig(
          name: '2026-2027 秋',
          startDate: DateTime(2026, 9, 14),
          totalWeeks: 30,
          periods: List.of(defaultPeriods),
        ),
        courses: courses,
      );
      final now = DateTime(2026, 9, 14, 8);
      final json = WidgetSync.buildSnapshotJson(tt, palette, now: now);
      final bytes = utf8.encode(json).length;
      final days = (jsonDecode(json)['days'] as List).cast<Map>();
      expect(days.length, 150);
      expect(
        days.every((d) => (d['courses'] as List).length == 12),
        isTrue,
        reason: '30 周学期里 150 天全在学期内、每天 12 节满课',
      );
      // Android 的 SharedPreferences 落盘是 XML，字符串里的 `"` 会被写成
      // `&quot;`（+5 字节），`&` / `<` 同理。估一下磁盘上的实际体积。
      final xmlBytes = utf8
          .encode(
            json
                .replaceAll('&', '&amp;')
                .replaceAll('<', '&lt;')
                .replaceAll('"', '&quot;'),
          )
          .length;
      debugPrint(
        '[widget snapshot size] 150 天 × 12 节满课 = $bytes 字节 '
        '(${(bytes / 1024).toStringAsFixed(1)} KB)，'
        'XML 转义后约 $xmlBytes 字节 '
        '(${(xmlBytes / 1024).toStringAsFixed(1)} KB)',
      );
      expect(bytes, lessThan(500 * 1024));
      expect(xmlBytes, lessThan(1024 * 1024));
    });
  });
}
