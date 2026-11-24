import 'package:shu_schedule/core/reminders/reminder_planner.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

/// 第 1 周周一 2026-09-14，18 周，内置 12 节作息（1: 08:00，3: 10:00，5: 13:00）。
/// 2026-10-07 是第 4 周周三。
Timetable buildTimetable({
  Map<String, DateOverride>? overrides,
  List<Course>? extra,
}) {
  final config = ScheduleConfig(
    name: '测试学期',
    startDate: DateTime(2026, 9, 14),
    totalWeeks: 18,
    overrides: overrides,
  );
  final all = <int>[for (var w = 1; w <= 18; w++) w];
  return Timetable(
    id: 't',
    name: '测试课表',
    config: config,
    courses: <Course>[
      Course(
        id: 'math',
        name: '高等数学',
        teacher: '张老师',
        location: 'A101',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: all,
      ),
      Course(
        id: 'eng',
        name: '大学英语',
        location: 'B202',
        day: 3,
        startPeriod: 3,
        endPeriod: 4,
        weeks: all,
      ),
      Course(
        id: 'pe',
        name: '体育',
        day: 4,
        startPeriod: 5,
        endPeriod: 5,
        weeks: all,
      ),
      ...?extra,
    ],
  );
}

/// 国庆后：10-10（周六）补周一的课，10-11（周日，本来就没课）停课，
/// 10-12（周一）运动会停课。
Map<String, DateOverride> octoberOverrides() => <String, DateOverride>{
  '2026-10-10': const DateOverride.actAs(weekday: 1, note: '国庆调休'),
  '2026-10-11': const DateOverride.cancelled(note: '国庆'),
  '2026-10-12': const DateOverride.cancelled(note: '运动会'),
};

List<PlannedReminder> classesOf(List<PlannedReminder> plan) =>
    plan.where((r) => r.kind == ReminderKind.classStart).toList();

List<PlannedReminder> previewsOf(List<PlannedReminder> plan) =>
    plan.where((r) => r.kind == ReminderKind.eveningPreview).toList();
