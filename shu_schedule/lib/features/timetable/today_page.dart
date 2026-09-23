import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/course.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/themed_background.dart';
import 'course_detail_sheet.dart';
import 'week_view_page.dart' show importRouteName;

/// 今日页：日期 + 周次 + 今天的课程列表，高亮下一节并显示倒计时。
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final colors = theme.colors;
    final timetable = appState.currentTimetable;
    final config = appState.currentConfig;
    final week = ScheduleUtils.rawWeekOf(_now, config);
    // 调休 / 停课：课程列表已经按它展开（coursesOn），这里只负责把它写出来。
    final effective = ScheduleUtils.effectiveDayOf(_now, config);
    final overrideText = effective.description == null
        ? ''
        : ' · ${effective.description}'
              '${effective.override?.note == null ? '' : '（${effective.override!.note}）'}';
    final courses = timetable == null
        ? const <Course>[]
        : ScheduleUtils.coursesOn(_now, timetable);
    final nextId = _nextCourseId(appState, courses);

    return ThemedBackground(
      theme: theme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${_now.month} 月 ${_now.day} 日 · '
                      '${weekdayNamesCn[_now.weekday]}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: colors.headerText,
                        fontFamily: theme.titleFontFamily,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      week < 1
                          ? '${config.name} · 还没开学'
                          : (week > config.totalWeeks
                                ? '${config.name} · 学期已结束'
                                : '${config.name} · 第 $week 周'
                                      '$overrideText'),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: timetable == null
                    ? EmptyState(
                        theme: theme,
                        emoji: '🌱',
                        title: '还没有课表',
                        message: '新学期，从第一门课开始。',
                        primaryLabel: '从教务导入',
                        onPrimary: () =>
                            Navigator.of(context).pushNamed(importRouteName),
                      )
                    : courses.isEmpty
                    ? EmptyState(
                        theme: theme,
                        emoji: theme.decor.emoji,
                        title: effective.cancelled
                            ? '今天停课。'
                            : (_now.weekday >= 6
                                  ? '周末留白，也是一种安排。'
                                  : '今天没有课程，留一点时间给自己。'),
                        message: '到课表页看看这一周的安排吧。',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: courses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _courseTile(
                          theme,
                          appState,
                          courses[i],
                          isNext: courses[i].id == nextId,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 今天剩下的第一门课（已经开始的不算）。
  String? _nextCourseId(AppState appState, List<Course> courses) {
    final nowMinutes = _now.hour * 60 + _now.minute;
    for (final c in courses) {
      final span = ScheduleUtils.periodRange(
        appState.currentConfig,
        c.startPeriod,
        c.endPeriod,
      );
      if (_minutesOf(span.start) > nowMinutes) return c.id;
    }
    return null;
  }

  Widget _courseTile(
    AppTheme theme,
    AppState appState,
    Course course, {
    required bool isNext,
  }) {
    final colors = theme.colors;
    final span = ScheduleUtils.periodRange(
      appState.currentConfig,
      course.startPeriod,
      course.endPeriod,
    );
    final nowMinutes = _now.hour * 60 + _now.minute;
    final startMinutes = _minutesOf(span.start);
    final endMinutes = _minutesOf(span.end);
    final ongoing = nowMinutes >= startMinutes && nowMinutes <= endMinutes;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(theme.cornerRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        onTap: () => showCourseDetailSheet(context, courses: <Course>[course]),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            border: Border.all(
              color: isNext ? colors.primary : colors.gridLine,
              width: isNext ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 6,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.courseColor(course.colorIndex),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      course.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${span.start}-${span.end} · '
                      '第 ${course.startPeriod}-${course.endPeriod} 节',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                    if (course.location != null || course.teacher != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          <String>[
                            if (course.location != null) course.location!,
                            if (course.teacher != null) course.teacher!,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (ongoing)
                _tag(theme, '正在上课', colors.accent)
              else if (isNext)
                _tag(
                  theme,
                  _countdownText(startMinutes - nowMinutes),
                  colors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(AppTheme theme, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: theme.colors.onPrimary),
    ),
  );

  static String _countdownText(int minutes) {
    if (minutes <= 0) return '即将开始';
    if (minutes < 60) return '$minutes 分钟后';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h 小时后' : '$h 小时 $m 分后';
  }

  static int _minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}
