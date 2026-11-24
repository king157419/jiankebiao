import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

/// v1.3.0 Phase A：调休 / 停课（`ScheduleConfig.overrides`）。
void main() {
  // 开学 2026-09-14（周一），18 周。
  Timetable build({Map<String, DateOverride>? overrides}) {
    final all = <int>[for (var w = 1; w <= 16; w++) w];
    return Timetable(
      id: 't',
      name: '调休测试',
      config: ScheduleConfig(
        name: '2026-2027 秋',
        startDate: DateTime(2026, 9, 14),
        totalWeeks: 18,
        overrides: overrides,
      ),
      courses: <Course>[
        Course(
          id: 'mon',
          name: '周一的课',
          day: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: all,
        ),
        Course(
          id: 'mon-odd',
          name: '周一单周课',
          day: 1,
          startPeriod: 3,
          endPeriod: 4,
          weeks: all.where((w) => w.isOdd).toList(),
        ),
        Course(
          id: 'thu',
          name: '周四的课',
          day: 4,
          startPeriod: 5,
          endPeriod: 6,
          weeks: all,
        ),
        Course(
          id: 'sat',
          name: '周六的课',
          day: 6,
          startPeriod: 1,
          endPeriod: 2,
          weeks: all,
        ),
      ],
    );
  }

  List<String> idsOn(DateTime date, Timetable tt) =>
      ScheduleUtils.coursesOn(date, tt).map((c) => c.id).toList();

  group('DateOverride 模型', () {
    test('toJson / fromJson 往返', () {
      const o = DateOverride(
        cancelled: false,
        actAsWeek: 5,
        actAsWeekday: 1,
        note: '国庆调休',
      );
      final back = DateOverride.fromJson(
        jsonDecode(jsonEncode(o.toJson())) as Map<String, dynamic>,
      );
      expect(back, o);
      expect(back.changesSchedule, isTrue);
      expect(back.shortLabel, '调休');
      expect(const DateOverride.cancelled().shortLabel, '停课');
      expect(const DateOverride(note: '只是备注').changesSchedule, isFalse);
      expect(const DateOverride(note: '只是备注').shortLabel, isNull);
    });

    test('脏数据：越界 / 类型不对的字段当 null', () {
      final o = DateOverride.fromJson(<String, dynamic>{
        'cancelled': 'yes',
        'actAsWeek': 0,
        'actAsWeekday': 9,
        'note': '   ',
      });
      expect(o.cancelled, isFalse);
      expect(o.actAsWeek, isNull);
      expect(o.actAsWeekday, isNull);
      expect(o.note, isNull);
      final s = DateOverride.fromJson(<String, dynamic>{
        'actAsWeek': '3',
        'actAsWeekday': 2.0,
      });
      expect(s.actAsWeek, 3);
      expect(s.actAsWeekday, 2);
    });
  });

  group('ScheduleConfig.overrides 读写', () {
    test('往返；key 归一化成 yyyy-MM-dd；非法条目丢弃', () {
      final cfg = ScheduleConfig.fromJson(<String, dynamic>{
        'name': 'x',
        'startDate': '2026-09-14',
        'overrides': <String, dynamic>{
          '2026-10-01': <String, dynamic>{'cancelled': true, 'note': '国庆'},
          '2026-10-10T00:00:00': <String, dynamic>{'actAsWeekday': 1},
          'not-a-date': <String, dynamic>{'cancelled': true},
          '2026-10-11': 'oops',
        },
      });
      expect(cfg.overrides.keys.toSet(), <String>{'2026-10-01', '2026-10-10'});
      expect(cfg.overrideOn(DateTime(2026, 10, 1))!.cancelled, isTrue);
      expect(cfg.overrideOn(DateTime(2026, 10, 10, 15, 30))!.actAsWeekday, 1);

      final back = ScheduleConfig.fromJson(
        jsonDecode(jsonEncode(cfg.toJson())) as Map<String, dynamic>,
      );
      expect(back.overrides, cfg.overrides);
    });

    test('v1.2.0 的旧 JSON 没有 overrides → 空表', () {
      final cfg = ScheduleConfig.fromJson(<String, dynamic>{
        'name': '2026-2027 秋',
        'startDate': '2026-09-14',
        'totalWeeks': 18,
        'showWeekend': true,
      });
      expect(cfg.overrides, isEmpty);
      expect(cfg.breakAfter, isNull);
    });

    test('withOverride 返回新对象，不改原配置；传 null 删除', () {
      final cfg = build().config;
      final a = cfg.withOverride(
        DateTime(2026, 10, 1),
        const DateOverride.cancelled(),
      );
      expect(cfg.overrides, isEmpty);
      expect(a.overrides.length, 1);
      final b = a.withOverride(DateTime(2026, 10, 1), null);
      expect(b.overrides, isEmpty);
      expect(a.overrides.length, 1);
    });

    test('copyWith 不共享 overrides 这张表', () {
      final cfg = build().config.withOverride(
        DateTime(2026, 10, 1),
        const DateOverride.cancelled(),
      );
      final copy = cfg.copyWith(name: 'y');
      copy.overrides.clear();
      expect(cfg.overrides.length, 1);
    });
  });

  group('effectiveDayOf / coursesOn', () {
    test('没有调休：和原来一样按日期推周次 / 星期', () {
      final tt = build();
      final e = ScheduleUtils.effectiveDayOf(
        DateTime(2026, 9, 14, 9),
        tt.config,
      );
      expect(e.week, 1);
      expect(e.calendarWeek, 1);
      expect(e.weekday, 1);
      expect(e.cancelled, isFalse);
      expect(e.isOverridden, isFalse);
      expect(e.label, isNull);
      expect(e.description, isNull);
      expect(idsOn(DateTime(2026, 9, 14), tt), <String>['mon', 'mon-odd']);
    });

    test('停课日：一门课都没有', () {
      final tt = build(
        overrides: <String, DateOverride>{
          '2026-10-01': const DateOverride.cancelled(note: '国庆节'),
        },
      );
      // 2026-10-01 是第 3 周周四，原本有「周四的课」。
      expect(idsOn(DateTime(2026, 9, 24), tt), <String>['thu']);
      expect(idsOn(DateTime(2026, 10, 1), tt), isEmpty);
      final e = ScheduleUtils.effectiveDayOf(DateTime(2026, 10, 1), tt.config);
      expect(e.cancelled, isTrue);
      expect(e.label, '停课');
      expect(e.description, '停课');
      expect(e.calendarWeek, 3);
    });

    test('国庆后周六上周一的课：周次沿用本周，星期换成周一', () {
      final tt = build(
        overrides: <String, DateOverride>{
          '2026-10-10': const DateOverride.actAs(weekday: 1),
        },
      );
      // 2026-10-10 是第 4 周周六（双周）：周一的课上，周一单周课不上，周六的课不上。
      expect(idsOn(DateTime(2026, 10, 10), tt), <String>['mon']);
      final e = ScheduleUtils.effectiveDayOf(DateTime(2026, 10, 10), tt.config);
      expect(e.week, 4);
      expect(e.weekday, 1);
      expect(e.label, '调休');
      expect(e.description, '调休，按周一上课');
    });

    test('按指定周 + 星期上课：补第 3 周（单周）的周一', () {
      final tt = build(
        overrides: <String, DateOverride>{
          '2026-10-10': const DateOverride.actAs(week: 3, weekday: 1),
        },
      );
      expect(idsOn(DateTime(2026, 10, 10), tt), <String>['mon', 'mon-odd']);
      final e = ScheduleUtils.effectiveDayOf(DateTime(2026, 10, 10), tt.config);
      expect(e.week, 3);
      expect(e.calendarWeek, 4);
      expect(e.description, '调休，按第 3 周周一上课');
    });

    test('只指定周次：星期沿用这一天自己的', () {
      final tt = build(
        overrides: <String, DateOverride>{
          // 2026-09-21 是第 2 周（双周）周一；按第 1 周上 → 单周课也上。
          '2026-09-21': const DateOverride.actAs(week: 1),
        },
      );
      expect(idsOn(DateTime(2026, 9, 21), tt), <String>['mon', 'mon-odd']);
      // 下一周（第 3 周，单周）没调休，照常。
      expect(idsOn(DateTime(2026, 9, 28), tt), <String>['mon', 'mon-odd']);
      // 第 4 周（双周）照常只有周一的课。
      expect(idsOn(DateTime(2026, 10, 5), tt), <String>['mon']);
    });

    test('只写备注不影响课程', () {
      final tt = build(
        overrides: <String, DateOverride>{
          '2026-09-14': const DateOverride(note: '开学第一天'),
        },
      );
      expect(idsOn(DateTime(2026, 9, 14), tt), <String>['mon', 'mon-odd']);
      expect(
        ScheduleUtils.effectiveDayOf(DateTime(2026, 9, 14), tt.config).label,
        isNull,
      );
    });

    test('开学前的调休日可以按学期内某一周上课', () {
      final tt = build(
        overrides: <String, DateOverride>{
          '2026-09-12': const DateOverride.actAs(week: 1, weekday: 1),
        },
      );
      expect(idsOn(DateTime(2026, 9, 12), tt), <String>['mon', 'mon-odd']);
      expect(idsOn(DateTime(2026, 9, 11), tt), isEmpty);
    });
  });
}
