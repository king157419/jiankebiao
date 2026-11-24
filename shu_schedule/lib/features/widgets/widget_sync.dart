import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/schedule_utils.dart';
import '../../models/course.dart';
import '../../models/period_time.dart';
import '../../models/schedule_config.dart';
import '../../models/timetable.dart';
import 'widget_palette.dart';

export 'widget_palette.dart' show WidgetPalette;

/// 把课表数据推送给 Android 桌面小组件。
///
/// 只有一份数据：`snapshot`（JSON 字符串）—— 从今天起覆盖整个学期的逐日课程
/// （调休 / 停课已展开，每节课带 `start` / `end` 时刻）+ 调色板 + 作息。
/// 两个原生小组件都直接读它渲染，**不需要 Flutter 引擎在跑**（翻页、跨天、
/// 「上课中 / N 分钟后上课」、今天上完自动看明天都在 Kotlin 侧按当前时间算）：
/// - `DayWidgetProvider`：4×2，某一天的课程列表；
/// - `NextWidgetProvider`：v1.4.0 的 2×1「下一节」。
///
/// v1.5.0 起两种都能在「设置 → 添加桌面小组件」的面板里一键添加（`add_widget_helper.dart`）。
///
/// v1.2.0 删掉了「本周课表」小组件，连带删掉了离屏渲染 PNG（`week_image`）那一步。
class WidgetSync {
  WidgetSync._();

  /// 快照在 home_widget SharedPreferences 里的 key。
  static const String snapshotKey = 'snapshot';

  /// 4×2 小组件 Provider 的类名（相对包名）。
  static const String dayProviderName = 'DayWidgetProvider';

  /// Kotlin 里 4×2 Provider 的完整类名（包名 + `.widgets.`）。
  static const String dayProviderQualified =
      'cn.shu.schedule.widgets.DayWidgetProvider';

  /// v1.4.0 2×1「下一节」Provider 的类名（相对包名）。
  static const String nextProviderName = 'NextWidgetProvider';

  /// Kotlin 里 2×1 Provider 的完整类名。
  static const String nextProviderQualified =
      'cn.shu.schedule.widgets.NextWidgetProvider';

  /// 推送后要通知刷新的所有 Provider。
  ///
  /// 少写一个的后果是那个小组件一直显示旧数据（系统 30 分钟周期才会兜底），
  /// 所以新增 Provider 时务必同步加到这里（widget_android_config_test 会核对
  /// 每一项在 AndroidManifest.xml 里都有 receiver）。没放到桌面上的 Provider
  /// 收到刷新只是查不到实例、直接返回，不会报错。
  static const List<String> refreshTargets = <String>[
    dayProviderQualified,
    nextProviderQualified,
  ];

  /// 快照最多覆盖多少天（今天起）。
  ///
  /// v1.2.0 只存 14 天，只看小组件、不开 App 的用户第 15 天就只剩「打开 App
  /// 刷新」。v1.3.0 起覆盖整学期，但封顶 150 天，控制 SharedPreferences 里
  /// 这一个 key 的体积（实测 150 天 × 每天 12 节满课 ≈ 403KB JSON，
  /// 见 widget_snapshot_term_test）。
  static const int maxSnapshotDays = 150;

  /// 快照覆盖的天数（今天起）：`min(totalWeeks * 7 + 7, 150)`。
  ///
  /// 多出来的 7 天保证学期最后一天往后翻 6 天（小组件的翻页上限）也翻得到。
  static int snapshotDaysFor(ScheduleConfig config) {
    final weeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
    return math.min(weeks * 7 + 7, maxSnapshotDays);
  }

  /// 快照 JSON 的结构版本，原生端可据此兼容旧数据。
  ///
  /// v2（1.3.0）：天数从固定 14 天变成整学期；每天多了 `label` / `note`
  /// （调休 / 停课），原生端不认识这两个字段也能照常显示。
  static const int snapshotVersion = 2;

  /// 生成快照 Map（纯函数，可单测）。
  ///
  /// [now] 只给测试用；生产代码传 null 取 `DateTime.now()`。
  static Map<String, dynamic> buildSnapshot(
    Timetable timetable,
    WidgetPalette palette, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final config = timetable.config;

    final periods = List<PeriodTime>.from(config.periods)
      ..sort((a, b) => a.index.compareTo(b.index));

    final days = <Map<String, dynamic>>[];
    final dayCount = snapshotDaysFor(config);
    for (var offset = 0; offset < dayCount; offset++) {
      // 必须用 ScheduleUtils.addDays：本机时区有夏令时，
      // `add(Duration(days:))` 会得到 23:00 这种错位日期（NOTES.md §2.1）。
      final date = ScheduleUtils.addDays(today, offset);
      // 调休 / 停课在这里展开，和周视图、上课提醒走同一个入口。
      final effective = ScheduleUtils.effectiveDayOf(date, config);
      final rawWeek = effective.calendarWeek;
      final inTerm = rawWeek >= 1 && rawWeek <= config.totalWeeks;
      // 课程看「实际按哪一周上」：调休到学期内某一周的日子照样有课。
      final effectiveInTerm =
          effective.week >= 1 && effective.week <= config.totalWeeks;

      final courses = <Map<String, dynamic>>[];
      if (effectiveInTerm) {
        for (final c in ScheduleUtils.coursesOnEffective(
          effective,
          timetable,
        )) {
          courses.add(_courseToJson(c, timetable, palette));
        }
      }

      final day = <String, dynamic>{
        'date': _isoDate(date),
        'weekday': date.weekday,
        'week': inTerm ? rawWeek : null,
        'courses': courses,
      };
      final label = effective.label;
      if (label != null) {
        day['label'] = label;
        day['note'] = effective.override?.note ?? effective.description;
      }
      days.add(day);
    }

    return <String, dynamic>{
      'version': snapshotVersion,
      'generatedAt': current.toIso8601String(),
      'timetableName': timetable.name,
      'termName': config.name,
      'totalWeeks': config.totalWeeks,
      'palette': palette.toJson(),
      'periods': periods
          .map(
            (p) => <String, dynamic>{
              'index': p.index,
              'start': p.start,
              'end': p.end,
            },
          )
          .toList(),
      'days': days,
    };
  }

  /// 生成快照 JSON 字符串。
  static String buildSnapshotJson(
    Timetable timetable,
    WidgetPalette palette, {
    DateTime? now,
  }) => jsonEncode(buildSnapshot(timetable, palette, now: now));

  /// 把课表推送到桌面小组件。
  ///
  /// 两步（各自独立捕获异常，一步失败不影响另一步）：
  /// 1. 写快照 JSON；
  /// 2. 通知 [refreshTargets] 里的所有 Provider 刷新。
  ///
  /// 永远不会抛异常；全部成功返回 true。
  static Future<bool> push(
    Timetable timetable,
    WidgetPalette palette, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    var ok = true;

    // 1. 快照
    try {
      final json = buildSnapshotJson(timetable, palette, now: current);
      final saved = await HomeWidget.saveWidgetData<String>(snapshotKey, json);
      if (saved == false) ok = false;
    } catch (e, st) {
      ok = false;
      _log('保存快照失败', e, st);
    }

    // 2. 刷新所有小组件
    for (final name in refreshTargets) {
      try {
        await HomeWidget.updateWidget(qualifiedAndroidName: name);
      } catch (e, st) {
        ok = false;
        _log('刷新小组件失败（$name）', e, st);
      }
    }

    return ok;
  }

  static Map<String, dynamic> _courseToJson(
    Course c,
    Timetable timetable,
    WidgetPalette palette,
  ) {
    final span = ScheduleUtils.periodRange(
      timetable.config,
      c.startPeriod,
      c.endPeriod,
    );
    return <String, dynamic>{
      'name': c.name,
      'location': c.location ?? '',
      'teacher': c.teacher ?? '',
      'startPeriod': c.startPeriod,
      'endPeriod': c.endPeriod,
      'start': span.start,
      'end': span.end,
      'color': WidgetPalette.hex(palette.courseColor(c.colorIndex)),
    };
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static void _log(String what, Object error, StackTrace stack) {
    debugPrint('[WidgetSync] $what: $error');
    assert(() {
      debugPrintStack(stackTrace: stack, maxFrames: 6);
      return true;
    }());
  }
}
