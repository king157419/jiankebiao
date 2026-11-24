import 'dart:convert';

import '../../models/course.dart';
import '../../models/reminder_settings.dart';
import '../../models/timetable.dart';
import '../presets.dart';
import '../schedule_utils.dart';

export '../../models/reminder_settings.dart';

/// 两个通知渠道（Android 8+ 的 NotificationChannel）。id 一旦发布就不能改：
/// 用户在系统设置里对渠道做的调整（静音、关闭）是按 id 记的。
class ReminderChannels {
  ReminderChannels._();

  /// 上课提醒：IMPORTANCE_HIGH（横幅 + 声音）。
  static const String classReminder = 'class_reminder';
  static const String classReminderName = '上课提醒';
  static const String classReminderDescription = '上课前按设定的分钟数提醒';

  /// 明日预告：IMPORTANCE_DEFAULT（有声音，不弹横幅）。
  static const String eveningPreview = 'evening_preview';
  static const String eveningPreviewName = '明日预告';
  static const String eveningPreviewDescription = '前一天晚上预告明天的课、停课和调休';
}

/// 提醒的种类。
enum ReminderKind {
  /// 上课前 N 分钟。
  classStart,

  /// 前一天晚上的明日预告。
  eveningPreview,

  /// 规划窗口最后一天晚上的「提醒已排到 x月x日，打开简课表就会续上」
  /// （v1.4.0 修复轮，review-G P2-1：没有后台任务，不打开 App 提醒会悄悄停掉）。
  horizonEnd,
}

/// 规划好的一条提醒（还没交给系统）。
class PlannedReminder {
  /// 稳定的通知 id（FNV-1a，见 [ReminderPlanner.stableId]）。
  final int id;

  /// 触发时刻（本地时间）。
  final DateTime fireAt;

  final String title;
  final String body;

  /// 通知渠道 id（[ReminderChannels]）。
  final String channel;

  /// 点通知时带回来的数据：`class|yyyy-MM-dd` / `preview|yyyy-MM-dd` /
  /// `today`（续排提醒）。
  final String payload;

  final ReminderKind kind;

  /// 这条提醒说的是哪一天：上课提醒 = 上课那天；明日预告 = 被预告的「明天」。
  final DateTime date;

  const PlannedReminder({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.channel,
    required this.payload,
    required this.kind,
    required this.date,
  });

  @override
  String toString() => 'PlannedReminder($id, $fireAt, $title | $body)';
}

/// 纯 Dart 的提醒规划器：给定课表、偏好和「现在」，算出接下来要发的全部提醒。
/// 不碰插件、不碰时钟，方便测试；真正交给系统的是 `ReminderService`。
///
/// 规则（PLAN-1.4 B2）：
/// - 从今天起 [defaultHorizonDays] 天内每一天，用 `ScheduleUtils.coursesOnEffective`
///   （调休 / 停课已展开，和周视图、小组件同一个入口）取课，
///   实际上课的周不在 `[1, totalWeeks]` 内的不提醒（和 `WidgetSync` 的学期守卫一致）；
/// - 每门课在 `periodRange(...).start − leadMinutes` 触发，`fireAt <= now` 的跳过；
/// - 明日预告：每天 `previewHour:previewMinute` 说「明天」，只在明天属于学期且
///   （有课 或 有调休 / 停课）时生成；停课日原本就没有课的不预告（见 [plan]）；
/// - 续排提醒：窗口最后一天的 `previewHour:previewMinute` 发一条
///   [horizonEndText]（渠道 `evening_preview`，payload [horizonEndPayload]），只在窗口之后
///   学期里还有课时生成——App 没有后台任务，不打开就不会再排新的提醒；
/// - 日期运算只用 `ScheduleUtils.addDays` / `DateTime(y, m, d, h, min)`：
///   开发机所在时区有夏令时（NOTES.md §2.1）。
///
/// 注意：[plan] **不看** [ReminderSettings.enabled]——总开关由 `ReminderService`
/// 判断；设置页也用它预览「开启后会提醒什么」。
class ReminderPlanner {
  ReminderPlanner._();

  /// 一次排多少天。Android 上每条都是一个闹钟（三星限 500 个；每天约 6 节课 +
  /// 1 条预告，14 天约 100 个），每次打开 / 回到 App 都会重排，窗口会往前滚。
  /// v1.4.0 修复轮从 10 天放宽到 14 天，并在窗口末尾加一条续排提醒。
  static const int defaultHorizonDays = 14;

  /// 续排提醒的 payload。`HomeShell` 对任何通知都一样处理：点开回到课表本周。
  ///
  /// 值 `'today'` 是 v1.4.0 留下来的内部标记（那时点开切到「今日」页，v1.5.0
  /// 删掉了今日页）。不改值：已经排进系统的旧通知带的就是它，照样能用。
  static const String horizonEndPayload = 'today';

  /// 续排提醒的标题（「即将触发」列表末尾显示同一句）。[lastDay] 是最后一天
  /// 排了上课提醒的日子。
  static String horizonEndText(DateTime lastDay) =>
      '提醒已排到 ${lastDay.month}月${lastDay.day}日，打开简课表就会续上';

  /// 往后找「窗口之后还有没有课」最多看多少天（一学期 + 余量）。
  static const int _lookAheadDays = 400;

  /// 明日预告的正文里最多列几门课。
  static const int _maxListed = 4;

  static List<PlannedReminder> plan({
    required Timetable? timetable,
    required ReminderSettings settings,
    required DateTime now,
    int horizonDays = defaultHorizonDays,
  }) {
    if (timetable == null || horizonDays <= 0) return const <PlannedReminder>[];
    final config = timetable.config;
    final today = DateTime(now.year, now.month, now.day);
    final out = <PlannedReminder>[];

    for (var i = 0; i < horizonDays; i++) {
      final date = ScheduleUtils.addDays(today, i);
      final day = ScheduleUtils.effectiveDayOf(date, config);

      for (final course in _coursesOf(day, timetable)) {
        final start = _startOf(timetable, course);
        if (start == null) continue;
        // DateTime 会把负的分钟数规整到前一个小时（甚至前一天），按墙上时间算。
        final fireAt = DateTime(
          date.year,
          date.month,
          date.day,
          start.hour,
          start.minute - settings.leadMinutes,
        );
        if (!fireAt.isAfter(now)) continue;
        out.add(
          PlannedReminder(
            id: stableId('class', date, course.id, course.startPeriod),
            fireAt: fireAt,
            title: '${course.name} · ${start.text} 上课',
            body: _classBody(course, day),
            channel: ReminderChannels.classReminder,
            payload: 'class|${ScheduleUtils.dateKey(date)}',
            kind: ReminderKind.classStart,
            date: date,
          ),
        );
      }

      if (settings.eveningPreview) {
        final fireAt = DateTime(
          date.year,
          date.month,
          date.day,
          settings.previewHour,
          settings.previewMinute,
        );
        if (fireAt.isAfter(now)) {
          final preview = _preview(
            timetable,
            ScheduleUtils.addDays(date, 1),
            fireAt,
          );
          if (preview != null) out.add(preview);
        }
      }
    }

    final end = _horizonEnd(timetable, settings, today, now, horizonDays);
    if (end != null) out.add(end);

    out.sort((a, b) {
      final t = a.fireAt.compareTo(b.fireAt);
      if (t != 0) return t;
      // 同一时刻（最后一晚的预告和续排提醒）续排排在后面。
      final ea = a.kind == ReminderKind.horizonEnd ? 1 : 0;
      final eb = b.kind == ReminderKind.horizonEnd ? 1 : 0;
      return ea != eb ? ea - eb : a.id.compareTo(b.id);
    });
    return out;
  }

  /// 窗口最后一天晚上的续排提醒；窗口之后学期里没有课了（或触发时刻已过）→ null。
  static PlannedReminder? _horizonEnd(
    Timetable timetable,
    ReminderSettings settings,
    DateTime today,
    DateTime now,
    int horizonDays,
  ) {
    final last = ScheduleUtils.addDays(today, horizonDays - 1);
    final fireAt = DateTime(
      last.year,
      last.month,
      last.day,
      settings.previewHour,
      settings.previewMinute,
    );
    if (!fireAt.isAfter(now)) return null;
    final next = ScheduleUtils.addDays(last, 1);
    if (!_hasClassesFrom(timetable, next)) return null;
    return PlannedReminder(
      id: stableId('horizon', last, '', 0),
      fireAt: fireAt,
      title: horizonEndText(last),
      body:
          '简课表只在打开或回到 App 时往后排 $horizonDays 天的提醒，'
          '${_dateText(next)}起的上课提醒还没排上',
      channel: ReminderChannels.eveningPreview,
      payload: horizonEndPayload,
      kind: ReminderKind.horizonEnd,
      date: last,
    );
  }

  /// [from] 当天或之后（学期内、含调休到学期内的日子）还有没有课。
  static bool _hasClassesFrom(Timetable timetable, DateTime from) {
    final config = timetable.config;
    var until = ScheduleUtils.addDays(
      config.startDate,
      config.totalWeeks * 7 - 1,
    );
    for (final key in config.overrides.keys) {
      final d = DateTime.tryParse(key);
      if (d != null && d.isAfter(until)) until = d;
    }
    for (var i = 0; i < _lookAheadDays; i++) {
      final date = ScheduleUtils.addDays(from, i);
      if (date.isAfter(until)) return false;
      final day = ScheduleUtils.effectiveDayOf(date, config);
      if (_coursesOf(day, timetable).isNotEmpty) return true;
    }
    return false;
  }

  /// 接下来 [horizonDays] 天里「停课、而且原本有课」的日子（设置页「即将触发」
  /// 里显示「x月x日 停课 · 不提醒」）。
  static List<DateTime> cancelledDays({
    required Timetable? timetable,
    required DateTime now,
    int horizonDays = defaultHorizonDays,
  }) {
    if (timetable == null) return const <DateTime>[];
    final today = DateTime(now.year, now.month, now.day);
    final out = <DateTime>[];
    for (var i = 0; i < horizonDays; i++) {
      final date = ScheduleUtils.addDays(today, i);
      final day = ScheduleUtils.effectiveDayOf(date, timetable.config);
      if (day.cancelled && _wouldHaveClasses(day, timetable)) out.add(date);
    }
    return out;
  }

  /// FNV-1a 32 位哈希，输入 `kind|yyyy-MM-dd|courseId|startPeriod`，
  /// 取低 31 位得到 Android 通知 id 要的非负 int。同一天同一门课永远是同一个 id，
  /// 重排时不会留下孤儿通知，也不会互相覆盖。
  static int stableId(
    String kind,
    DateTime date,
    String courseId,
    int startPeriod,
  ) {
    final input = '$kind|${ScheduleUtils.dateKey(date)}|$courseId|$startPeriod';
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  // ------------------------------------------------------------------ 内部

  /// 实际上课的周在学期内才有课（停课日 / 开学前 / 学期后为空）。
  static List<Course> _coursesOf(EffectiveDay day, Timetable timetable) {
    if (day.week < 1 || day.week > timetable.config.totalWeeks) {
      return const <Course>[];
    }
    return ScheduleUtils.coursesOnEffective(day, timetable);
  }

  /// 不考虑调休 / 停课时，这一天原本有没有课。
  static bool _wouldHaveClasses(EffectiveDay day, Timetable timetable) {
    final plain = EffectiveDay(
      date: day.date,
      calendarWeek: day.calendarWeek,
      week: day.calendarWeek,
      weekday: day.date.weekday,
      cancelled: false,
    );
    return _coursesOf(plain, timetable).isNotEmpty;
  }

  static _Hm? _startOf(Timetable timetable, Course course) {
    final span = ScheduleUtils.periodRange(
      timetable.config,
      course.startPeriod,
      course.endPeriod,
    );
    return _Hm.parse(span.start);
  }

  static String _periodText(Course c) => c.startPeriod == c.endPeriod
      ? '第 ${c.startPeriod} 节'
      : '第 ${c.startPeriod}-${c.endPeriod} 节';

  /// 调休日的「按第 N 周周X上课」。
  static String _actAsText(EffectiveDay day) =>
      '按第 ${day.week} 周${weekdayNamesCn[day.weekday.clamp(1, 7)]}上课';

  static String _classBody(Course course, EffectiveDay day) {
    final parts = <String>[
      if ((course.location ?? '').trim().isNotEmpty) course.location!.trim(),
      if ((course.teacher ?? '').trim().isNotEmpty) course.teacher!.trim(),
      _periodText(course),
    ];
    final adjusted = day.isOverridden && !day.cancelled;
    return parts.join(' · ') + (adjusted ? '（调休：${_actAsText(day)}）' : '');
  }

  static String _dateText(DateTime d) =>
      '${d.month}月${d.day}日 ${weekdayNamesCn[d.weekday]}';

  static PlannedReminder? _preview(
    Timetable timetable,
    DateTime tomorrow,
    DateTime fireAt,
  ) {
    final config = timetable.config;
    final day = ScheduleUtils.effectiveDayOf(tomorrow, config);
    final calendarInTerm =
        day.calendarWeek >= 1 && day.calendarWeek <= config.totalWeeks;
    final actualInTerm = day.week >= 1 && day.week <= config.totalWeeks;
    if (!calendarInTerm && !actualInTerm) return null;

    final courses = _coursesOf(day, timetable);
    final String title;
    final String body;
    if (day.cancelled) {
      // 原本就没课的日子停课（比如长假里的周日）不打扰。
      if (!_wouldHaveClasses(day, timetable)) return null;
      final note = day.override?.note?.trim() ?? '';
      title = note.isEmpty ? '明天停课' : '明天停课（$note）';
      body = '${_dateText(tomorrow)}不上课，当天不会有上课提醒';
    } else if (day.isOverridden) {
      final head = '明天${_actAsText(day)}';
      if (courses.isEmpty) {
        title = '$head，没有课';
        body = '${_dateText(tomorrow)}按调休没有课';
      } else {
        final first = _startOf(timetable, courses.first);
        title =
            '$head，共 ${courses.length} 节课，'
            '${first?.text ?? ''} 开始';
        body = '${_dateText(tomorrow)} · ${_listText(timetable, courses)}';
      }
    } else {
      if (courses.isEmpty) return null;
      final first = _startOf(timetable, courses.first);
      title =
          '明天 ${courses.length} 节课，'
          '${first?.text ?? ''} ${courses.first.name}';
      body = '${_dateText(tomorrow)} · ${_listText(timetable, courses)}';
    }
    return PlannedReminder(
      id: stableId('preview', tomorrow, '', 0),
      fireAt: fireAt,
      title: title,
      body: body,
      channel: ReminderChannels.eveningPreview,
      payload: 'preview|${ScheduleUtils.dateKey(tomorrow)}',
      kind: ReminderKind.eveningPreview,
      date: tomorrow,
    );
  }

  static String _listText(Timetable timetable, List<Course> courses) {
    final shown = courses.take(_maxListed).map((c) {
      final t = _startOf(timetable, c)?.text ?? '';
      return '$t ${c.name}'.trim();
    }).toList();
    final more = courses.length - shown.length;
    return shown.join('、') + (more > 0 ? ' 等 ${courses.length} 节课' : '');
  }
}

/// 「HH:mm」解析结果。
class _Hm {
  final int hour;
  final int minute;
  const _Hm(this.hour, this.minute);

  static _Hm? parse(String text) {
    final parts = text.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return _Hm(h, m);
  }

  String get text =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
