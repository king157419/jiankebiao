import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/reminders/reminder_planner.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/period_time.dart';
import 'package:shu_schedule/models/schedule_config.dart';

import 'helpers/reminder_fixtures.dart';

void main() {
  const settings = ReminderSettings(enabled: true);
  final wedMorning = DateTime(2026, 10, 7, 7);

  group('上课提醒', () {
    test('普通日：开课前 15 分钟，标题 / 正文 / 渠道 / payload', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: wedMorning,
      );
      final first = plan.first;
      expect(first.kind, ReminderKind.classStart);
      expect(first.fireAt, DateTime(2026, 10, 7, 9, 45));
      expect(first.title, '大学英语 · 10:00 上课');
      expect(first.body, 'B202 · 第 3-4 节');
      expect(first.channel, ReminderChannels.classReminder);
      expect(first.payload, 'class|2026-10-07');
      expect(first.date, DateTime(2026, 10, 7));

      final pe = classesOf(plan)[1];
      expect(pe.fireAt, DateTime(2026, 10, 8, 12, 45));
      expect(pe.title, '体育 · 13:00 上课');
      expect(pe.body, '第 5 节', reason: '没有地点和老师时只写节次；单节写「第 5 节」');
    });

    test('地点 + 老师都有：「地点 · 老师 · 第 s-e 节」', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: DateTime(2026, 10, 4, 22), // 周日晚上
      );
      final math = classesOf(plan).first;
      expect(math.fireAt, DateTime(2026, 10, 5, 7, 45));
      expect(math.body, 'A101 · 张老师 · 第 1-2 节');
    });

    test('提前分钟数生效（30 分钟）', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings.copyWith(leadMinutes: 30),
        now: wedMorning,
      );
      expect(classesOf(plan).first.fireAt, DateTime(2026, 10, 7, 9, 30));
    });

    test('fireAt <= now 的跳过（恰好等于也跳过），课还没开始也一样', () {
      final atFire = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: DateTime(2026, 10, 7, 9, 45),
      );
      expect(
        classesOf(atFire).where((r) => r.date == DateTime(2026, 10, 7)),
        isEmpty,
      );
      final before = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: DateTime(2026, 10, 7, 9, 44, 59),
      );
      expect(classesOf(before).first.date, DateTime(2026, 10, 7));
    });

    test('停课日没有上课提醒；调休日按目标星期出课并注明', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(overrides: octoberOverrides()),
        settings: settings,
        now: wedMorning,
      );
      final classes = classesOf(plan);
      expect(
        classes.where((r) => r.date == DateTime(2026, 10, 12)),
        isEmpty,
        reason: '10-12 周一停课',
      );
      final sat = classes.singleWhere((r) => r.date == DateTime(2026, 10, 10));
      expect(sat.title, '高等数学 · 08:00 上课');
      expect(sat.fireAt, DateTime(2026, 10, 10, 7, 45));
      expect(sat.body, 'A101 · 张老师 · 第 1-2 节（调休：按第 4 周周一上课）');
    });

    test('14 天窗口：今天起 14 天（含今天），按时间排序', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(overrides: octoberOverrides()),
        settings: settings,
        now: wedMorning,
      );
      final classes = classesOf(plan);
      expect(
        classes.map((r) => ScheduleUtils.dateKey(r.date)).toList(),
        <String>[
          '2026-10-07',
          '2026-10-08',
          '2026-10-10',
          '2026-10-14',
          '2026-10-15',
          '2026-10-19',
        ],
      );
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].fireAt.isBefore(plan[i - 1].fireAt), isFalse);
      }
      expect(ReminderPlanner.defaultHorizonDays, 14);
      expect(
        plan.every((r) => r.fireAt.isBefore(DateTime(2026, 10, 21))),
        isTrue,
      );
    });

    test('学期结束后不提醒（课程周次超出总周数也一样）', () {
      final tt = buildTimetable(
        extra: <Course>[
          Course(
            id: 'late',
            name: '补课',
            day: 1,
            startPeriod: 1,
            endPeriod: 1,
            weeks: <int>[for (var w = 1; w <= 20; w++) w],
          ),
        ],
      );
      // 第 18 周周日是 2027-01-17；第 19 周周一 2027-01-18 不在学期内。
      final plan = ReminderPlanner.plan(
        timetable: tt,
        settings: settings,
        now: DateTime(2027, 1, 15, 22),
      );
      expect(
        plan.where((r) => !r.date.isBefore(DateTime(2027, 1, 18))),
        isEmpty,
      );
    });

    test('没有课表 / 窗口为 0 → 空', () {
      expect(
        ReminderPlanner.plan(
          timetable: null,
          settings: settings,
          now: wedMorning,
        ),
        isEmpty,
      );
      expect(
        ReminderPlanner.plan(
          timetable: buildTimetable(),
          settings: settings,
          now: wedMorning,
          horizonDays: 0,
        ),
        isEmpty,
      );
    });

    test('提前分钟跨午夜：00:10 的课提前 15 分钟 → 前一天 23:55，日期仍是上课那天', () {
      final tt = buildTimetable(
        extra: <Course>[
          Course(
            id: 'night',
            name: '天文观测',
            day: 4,
            startPeriod: 1,
            endPeriod: 1,
            weeks: <int>[for (var w = 1; w <= 18; w++) w],
          ),
        ],
      );
      tt.config.periods[0] = const PeriodTime(
        index: 1,
        start: '00:10',
        end: '00:55',
      );
      final plan = ReminderPlanner.plan(
        timetable: tt,
        settings: settings,
        now: wedMorning,
        horizonDays: 2,
      );
      final night = classesOf(plan)
          .singleWhere((r) => r.title.startsWith('天文观测'));
      expect(night.fireAt, DateTime(2026, 10, 7, 23, 55));
      expect(night.date, DateTime(2026, 10, 8));
      expect(night.title, '天文观测 · 00:10 上课');
      expect(night.payload, 'class|2026-10-08');
    });

    test('调休到第 totalWeeks+1 周：不出上课提醒（和 ICS、小组件的学期守卫一致）', () {
      final tt = buildTimetable(
        overrides: <String, DateOverride>{
          '2026-10-17': const DateOverride.actAs(week: 19, weekday: 1),
        },
        extra: <Course>[
          Course(
            id: 'w19',
            name: '第 19 周的课',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: const <int>[19, 20],
          ),
        ],
      );
      final plan = ReminderPlanner.plan(
        timetable: tt,
        settings: settings,
        now: wedMorning,
      );
      expect(
        classesOf(plan).where((r) => r.date == DateTime(2026, 10, 17)),
        isEmpty,
      );
      expect(plan.where((r) => r.title.startsWith('第 19 周的课')), isEmpty);
    });

    test('跨夏令时（开发机时区 11-01 回拨）仍按墙上时间提醒', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: DateTime(2026, 10, 30, 22),
        horizonDays: 5,
      );
      final mon = classesOf(plan)
          .singleWhere((r) => r.date == DateTime(2026, 11, 2));
      expect(mon.fireAt.hour, 7);
      expect(mon.fireAt.minute, 45);
      expect(mon.fireAt.day, 2);
      expect(classesOf(plan).map((r) => r.date.hour).toSet(), <int>{
        0,
      }, reason: '日期都在 00:00，没有 23:00 错位');
    });
  });

  group('明日预告', () {
    test('普通：「明天 k 节课，首节时间 首节课名」，21:00 触发', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: wedMorning,
      );
      final p = previewsOf(plan).first;
      expect(p.fireAt, DateTime(2026, 10, 7, 21));
      expect(p.date, DateTime(2026, 10, 8));
      expect(p.title, '明天 1 节课，13:00 体育');
      expect(p.body, '10月8日 周四 · 13:00 体育');
      expect(p.channel, ReminderChannels.eveningPreview);
      expect(p.payload, 'preview|2026-10-08');
    });

    test('停课：「明天停课（备注）」；调休：「明天按第 N 周周X上课，共 k 节课，… 开始」', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(overrides: octoberOverrides()),
        settings: settings,
        now: wedMorning,
      );
      final byDate = <String, PlannedReminder>{
        for (final p in previewsOf(plan)) ScheduleUtils.dateKey(p.date): p,
      };
      expect(byDate['2026-10-10']!.title, '明天按第 4 周周一上课，共 1 节课，08:00 开始');
      expect(byDate['2026-10-10']!.fireAt, DateTime(2026, 10, 9, 21));
      expect(byDate['2026-10-12']!.title, '明天停课（运动会）');
      expect(byDate['2026-10-12']!.body, contains('不会有上课提醒'));
      expect(
        byDate.containsKey('2026-10-11'),
        isFalse,
        reason: '10-11 周日本来就没课，停课不打扰',
      );
      expect(
        byDate.containsKey('2026-10-09'),
        isFalse,
        reason: '明天既没课也没调休 → 不生成',
      );
      expect(byDate.keys.toList()..sort(), <String>[
        '2026-10-08',
        '2026-10-10',
        '2026-10-12',
        '2026-10-14',
        '2026-10-15',
        '2026-10-19',
        '2026-10-21',
      ], reason: '窗口最后一天（10-20）晚上预告 10-21');
    });

    test('停课没写备注 →「明天停课」', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(
          overrides: <String, DateOverride>{
            '2026-10-08': const DateOverride.cancelled(),
          },
        ),
        settings: settings,
        now: wedMorning,
      );
      expect(previewsOf(plan).first.title, '明天停课');
    });

    test('预告时间可改；关掉预告就没有', () {
      final at2030 = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings.copyWith(previewHour: 20, previewMinute: 30),
        now: wedMorning,
      );
      expect(previewsOf(at2030).first.fireAt, DateTime(2026, 10, 7, 20, 30));
      final off = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings.copyWith(eveningPreview: false),
        now: wedMorning,
      );
      expect(previewsOf(off), isEmpty);
    });

    test('今晚的预告时间已过 → 跳过今晚那条', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: DateTime(2026, 10, 7, 21, 0, 1),
      );
      expect(
        previewsOf(plan).where((p) => p.date == DateTime(2026, 10, 8)),
        isEmpty,
      );
    });

    test('开学前一晚：预告第 1 周周一的课', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: DateTime(2026, 9, 13, 8), // 开学前一天（周日）
      );
      final first = previewsOf(plan).first;
      expect(first.fireAt, DateTime(2026, 9, 13, 21));
      expect(first.date, DateTime(2026, 9, 14));
      expect(first.title, '明天 1 节课，08:00 高等数学');
      expect(first.payload, 'preview|2026-09-14');
    });

    test('学期后第一天不预告', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: DateTime(2027, 1, 17, 8), // 第 18 周周日
      );
      expect(previewsOf(plan), isEmpty);
    });
  });

  group('续排提醒（窗口末尾）', () {
    test('最后一天 previewHour 发「提醒已排到 x月x日，打开简课表就会续上」', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(overrides: octoberOverrides()),
        settings: settings,
        now: wedMorning,
      );
      final ends = plan
          .where((r) => r.kind == ReminderKind.horizonEnd)
          .toList();
      expect(ends, hasLength(1));
      final end = ends.single;
      expect(end.fireAt, DateTime(2026, 10, 20, 21));
      expect(end.date, DateTime(2026, 10, 20));
      expect(end.title, '提醒已排到 10月20日，打开简课表就会续上');
      expect(end.title, ReminderPlanner.horizonEndText(DateTime(2026, 10, 20)));
      expect(end.body, contains('10月21日 周三起的上课提醒还没排上'));
      expect(end.channel, ReminderChannels.eveningPreview);
      expect(end.payload, 'today');
      expect(
        plan.last.kind,
        ReminderKind.horizonEnd,
        reason: '窗口里最晚的一条：和最后一晚的预告同一时刻，排在预告后面',
      );
    });

    test('id 稳定：同一天换个「现在」/ 提前分钟重算不变，且是独立实现算出的值', () {
      final tt = buildTimetable(overrides: octoberOverrides());
      PlannedReminder endOf(List<PlannedReminder> plan) =>
          plan.singleWhere((r) => r.kind == ReminderKind.horizonEnd);
      final a = endOf(
        ReminderPlanner.plan(
          timetable: tt,
          settings: settings,
          now: wedMorning,
        ),
      );
      final b = endOf(
        ReminderPlanner.plan(
          timetable: tt,
          settings: settings.copyWith(leadMinutes: 5, eveningPreview: false),
          now: DateTime(2026, 10, 7, 20, 30),
        ),
      );
      expect(b.id, a.id);
      expect(
        a.id,
        1820131927,
        reason: 'FNV-1a(horizon|2026-10-20||0)，Python 复算',
      );
      expect(
        ReminderPlanner.stableId('horizon', DateTime(2026, 10, 20), '', 0),
        a.id,
      );
      // 第二天打开 App：窗口往后滚一天，续排提醒也换成新的一天。
      final next = endOf(
        ReminderPlanner.plan(
          timetable: tt,
          settings: settings,
          now: DateTime(2026, 10, 8, 7),
        ),
      );
      expect(next.date, DateTime(2026, 10, 21));
      expect(next.id, isNot(a.id));
    });

    test('窗口之后学期里没课了 → 不发续排提醒', () {
      final plan = ReminderPlanner.plan(
        timetable: buildTimetable(),
        settings: settings,
        now: DateTime(2027, 1, 5, 7), // 第 17 周周二，窗口盖到学期结束之后
      );
      expect(plan.where((r) => r.kind == ReminderKind.horizonEnd), isEmpty);
    });
  });

  group('id', () {
    test('FNV-1a 32 位，取低 31 位（和独立实现的结果一致）', () {
      expect(
        ReminderPlanner.stableId('class', DateTime(2026, 10, 7), 'eng', 3),
        70524834,
      );
      expect(
        ReminderPlanner.stableId('preview', DateTime(2026, 10, 12), '', 0),
        81935415,
      );
    });

    test('稳定：换个「现在」重算，同一天同一门课 id 不变；不同天 / 种类不撞', () {
      final tt = buildTimetable(overrides: octoberOverrides());
      final a = ReminderPlanner.plan(
        timetable: tt,
        settings: settings,
        now: wedMorning,
      );
      final b = ReminderPlanner.plan(
        timetable: tt,
        settings: settings.copyWith(leadMinutes: 5),
        now: DateTime(2026, 10, 7, 8),
      );
      final idsA = {for (final r in a) r.payload + r.title: r.id};
      final idsB = {for (final r in b) r.payload + r.title: r.id};
      for (final key in idsA.keys) {
        if (idsB.containsKey(key)) expect(idsB[key], idsA[key], reason: key);
      }
      expect(a.map((r) => r.id).toSet().length, a.length, reason: 'id 不重复');
      expect(a.every((r) => r.id >= 0 && r.id <= 0x7fffffff), isTrue);
    });
  });

  group('停课日列表', () {
    test('只列「停课且原本有课」的日子', () {
      final days = ReminderPlanner.cancelledDays(
        timetable: buildTimetable(overrides: octoberOverrides()),
        now: wedMorning,
      );
      expect(days, <DateTime>[DateTime(2026, 10, 12)]);
    });
  });

  group('ReminderSettings', () {
    test('默认值、JSON 往返、脏数据回默认', () {
      const d = ReminderSettings();
      expect(d.enabled, isFalse);
      expect(d.leadMinutes, 15);
      expect(d.eveningPreview, isTrue);
      expect(d.previewTimeText, '21:00');
      const s = ReminderSettings(
        enabled: true,
        leadMinutes: 30,
        eveningPreview: false,
        previewHour: 7,
        previewMinute: 5,
      );
      expect(ReminderSettings.fromJson(s.toJson()), s);
      expect(s.previewTimeText, '07:05');
      expect(ReminderSettings.fromJson(null), d);
      expect(ReminderSettings.fromJson('x'), d);
      expect(
        ReminderSettings.fromJson(<String, dynamic>{
          'enabled': 'yes',
          'leadMinutes': 7,
          'previewHour': 24,
          'previewMinute': -1,
          'eveningPreview': 1,
        }),
        d,
      );
    });
  });
}
