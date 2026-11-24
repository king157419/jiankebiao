import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/holiday_presets.dart';
import '../../core/holiday_repository.dart';
import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/schedule_config.dart';
import '../settings/date_override_editor.dart';
import '../settings/date_override_flow.dart';

/// 假日表对某一天的建议，整理成长按面板最上面的一行（v1.4.0）。
class DayHolidaySuggestion {
  /// 「假期表建议：按 10/6（周二）课表上课」/「假期表建议：停课（国庆节）」/
  /// 「假期表建议：国家调休上班日」。
  final String title;

  /// 备注 · 来源，以及需要注意的问题。
  final String detail;

  /// 一键套用的规则。国家调休上班日为 null：学校按哪天的课上要看通知，
  /// 点这一行打开编辑器手动选。
  final DateOverride? override;

  /// 这一天已经是这个设置了。
  final bool alreadyApplied;

  const DayHolidaySuggestion({
    required this.title,
    required this.detail,
    this.override,
    this.alreadyApplied = false,
  });
}

/// 从假日表里取 [date] 这一天的建议（和「套用节假日安排」同一套规则：
/// 课表有 `schoolId` 且学校数据对得上当前学期时用学校通知，否则用国家安排）。
/// 这一天不在学期内、或假日表里没有这一天时返回 null。
DayHolidaySuggestion? daySuggestionOf(
  HolidayPresets presets,
  ScheduleConfig config,
  DateTime date, {
  String? schoolId,
}) {
  final key = ScheduleUtils.dateKey(date);
  HolidaySuggestion? item;
  for (final s in presets.planFor(config: config, schoolId: schoolId).items) {
    if (ScheduleUtils.dateKey(s.date) == key) {
      item = s;
      break;
    }
  }
  if (item == null) return null;
  final o = item.override;
  final details = <String>[
    if (item.fromSchool) ...<String>[?item.note, item.sourceLabel] else
      ?item.note,
    if (item.warning != null) '注意：${item.warning}',
  ];
  final String title;
  if (o == null) {
    title = '假期表建议：国家调休上班日';
  } else if (o.cancelled) {
    final reason = _shortReason(item.note);
    title = reason == null ? '假期表建议：停课' : '假期表建议：停课（$reason）';
  } else {
    title = '假期表建议：${_actAsText(config, o)}';
  }
  return DayHolidaySuggestion(
    title: title,
    detail: details.join(' · '),
    override: o,
    alreadyApplied: item.alreadyApplied,
  );
}

/// 「按 10/6（周二）课表上课」/「按周二课表上课」/「按第 4 周课表上课」。
String _actAsText(ScheduleConfig config, DateOverride o) {
  final week = o.actAsWeek;
  final weekday = o.actAsWeekday;
  if (week != null && weekday != null) {
    final d = ScheduleUtils.addDays(
      config.startDate,
      (week - 1) * 7 + (weekday - 1),
    );
    return '按 ${d.month}/${d.day}（${weekdayNamesCn[weekday]}）课表上课';
  }
  if (weekday != null) return '按${weekdayNamesCn[weekday]}课表上课';
  return '按第 $week 周课表上课';
}

/// 「国庆节放假（国家安排）」→「国庆节」；「中秋节放假」→「中秋节」；
/// 没有「放假」两个字的备注原样用；空的返回 null。
String? _shortReason(String? note) {
  if (note == null) return null;
  var s = note.replaceAll('（国家安排）', '').trim();
  final i = s.indexOf('放假');
  if (i > 0) s = s.substring(0, i);
  s = s.trim();
  return s.isEmpty ? null : s;
}

/// 面板标题：「10月8日 周四 · 第 4 周」（不在学期内时写「不在本学期」）。
String dayOverrideSheetTitle(DateTime date, ScheduleConfig config) {
  final week = ScheduleUtils.rawWeekOf(date, config);
  final weekText = week >= 1 && week <= config.totalWeeks
      ? '第 $week 周'
      : '不在本学期';
  return '${date.month}月${date.day}日 ${weekdayNamesCn[date.weekday]} · $weekText';
}

/// 当前状态：「当前：停课（运动会）」/「当前：调休，按周一上课 · 当天 3 节课」/
/// 「当前：按原课表上课 · 当天没有课」。[courseCount] 为 null 时不写课数。
String dayOverrideStateText(EffectiveDay day, {int? courseCount}) {
  final note = day.override?.note;
  final buf = StringBuffer('当前：');
  if (day.isOverridden) {
    buf.write(day.description);
    if (note != null) buf.write('（$note）');
  } else {
    buf.write('按原课表上课');
    if (note != null) buf.write('（备注：$note）');
  }
  if (courseCount != null && !day.cancelled) {
    buf.write(courseCount == 0 ? ' · 当天没有课' : ' · 当天 $courseCount 节课');
  }
  return buf.toString();
}

/// 长按面板里点了哪一项。
enum DayOverrideAction {
  /// 套用假日表建议（[DayOverrideChoice.override]）。
  suggest,

  /// 设为停课。
  cancel,

  /// 打开编辑器，预置「按某个星期上课」。
  actAs,

  /// 打开完整编辑器。
  edit,

  /// 清除这一天的设置。
  clear,
}

class DayOverrideChoice {
  final DayOverrideAction action;
  final DateOverride? override;

  const DayOverrideChoice(this.action, [this.override]);
}

/// 周视图长按列头：弹出 [DayOverrideSheet]，按选择改这一天的调休 / 停课。
///
/// 一键操作（套用建议 / 设为停课 / 清除）之后弹 SnackBar，可以「撤销」；
/// 「调休：按某天课表上课」「编辑…」走 [editDateOverride]（和学期设置页同一个流程）。
/// [holidays] 只给测试注入；不传时用默认仓库（内置或已更新的假日表）。
Future<void> showDayOverrideSheet(
  BuildContext context,
  DateTime date, {
  HolidayRepository? holidays,
}) async {
  final appState = context.read<AppState>();
  final day = DateTime(date.year, date.month, date.day);
  final choice = await showModalBottomSheet<DayOverrideChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DayOverrideSheet(
      key: const ValueKey<String>('override-sheet'),
      date: day,
      holidays: holidays,
    ),
  );
  if (choice == null || !context.mounted) return;
  final label = '${day.month}月${day.day}日';
  switch (choice.action) {
    case DayOverrideAction.suggest:
      final o = choice.override;
      if (o == null) return;
      await _setWithUndo(
        context,
        appState,
        day,
        o,
        '已按假期表把 $label 设为「${describeDateOverride(o)}」',
      );
    case DayOverrideAction.cancel:
      await _setWithUndo(
        context,
        appState,
        day,
        const DateOverride.cancelled(),
        '已把 $label 设为停课',
      );
    case DayOverrideAction.actAs:
      await editDateOverride(
        context,
        appState,
        date: day,
        initialMode: OverrideMode.weekday,
      );
    case DayOverrideAction.edit:
      await editDateOverride(context, appState, date: day);
    case DayOverrideAction.clear:
      await _setWithUndo(context, appState, day, null, '已清除 $label 的设置');
  }
}

Future<void> _setWithUndo(
  BuildContext context,
  AppState appState,
  DateTime date,
  DateOverride? value,
  String message,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final previous = appState.currentConfig.overrideOn(date);
  await appState.setDateOverride(date, value);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => appState.setDateOverride(date, previous),
        ),
      ),
    );
}

/// 长按列头的底部面板（key `override-sheet`）。点一项就 pop 出 [DayOverrideChoice]，
/// 真正的修改由 [showDayOverrideSheet] 在面板关掉之后做。
class DayOverrideSheet extends StatefulWidget {
  final DateTime date;
  final HolidayRepository? holidays;

  const DayOverrideSheet({super.key, required this.date, this.holidays});

  @override
  State<DayOverrideSheet> createState() => _DayOverrideSheetState();
}

class _DayOverrideSheetState extends State<DayOverrideSheet> {
  late final Future<HolidayPresets> _presets =
      (widget.holidays ?? HolidayRepository()).load();

  void _pick(DayOverrideAction action, [DateOverride? override]) =>
      Navigator.of(context).pop(DayOverrideChoice(action, override));

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.watch<ThemeController>().current.colors;
    final timetable = appState.currentTimetable;
    final config = appState.currentConfig;
    final date = widget.date;
    final effective = ScheduleUtils.effectiveDayOf(date, config);
    final hasSetting = config.overrideOn(date) != null;
    final courseCount = timetable == null
        ? null
        : ScheduleUtils.coursesOnEffective(effective, timetable).length;
    final muted = TextStyle(fontSize: 12, color: colors.onSurfaceMuted);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                dayOverrideSheetTitle(date, config),
                key: const ValueKey<String>('override-sheet-title'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                dayOverrideStateText(effective, courseCount: courseCount),
                key: const ValueKey<String>('override-sheet-state'),
                style: TextStyle(fontSize: 13, color: colors.onSurfaceMuted),
              ),
            ),
            FutureBuilder<HolidayPresets>(
              future: _presets,
              builder: (context, snapshot) {
                final presets = snapshot.data;
                if (presets == null) return const SizedBox.shrink();
                final s = daySuggestionOf(
                  presets,
                  config,
                  date,
                  schoolId: timetable?.schoolId,
                );
                if (s == null) return const SizedBox.shrink();
                return ListTile(
                  key: const ValueKey<String>('override-sheet-suggest'),
                  leading: Icon(
                    Icons.auto_awesome_outlined,
                    color: colors.accent,
                  ),
                  title: Text(s.title),
                  subtitle: Text(
                    s.alreadyApplied
                        ? '已是这个设置'
                        : (s.override == null
                              ? '${s.detail} · 点这里选按哪天的课上'
                              : s.detail),
                    style: muted,
                  ),
                  enabled: !s.alreadyApplied,
                  onTap: () => s.override == null
                      ? _pick(DayOverrideAction.actAs)
                      : _pick(DayOverrideAction.suggest, s.override),
                );
              },
            ),
            ListTile(
              key: const ValueKey<String>('override-sheet-cancel'),
              leading: Icon(Icons.event_busy_outlined, color: colors.danger),
              title: const Text('设为停课'),
              subtitle: Text(
                effective.cancelled ? '这一天已经是停课' : '这一天的课全部不显示，可以撤销',
                style: muted,
              ),
              enabled: !effective.cancelled,
              onTap: () => _pick(DayOverrideAction.cancel),
            ),
            ListTile(
              key: const ValueKey<String>('override-sheet-actas'),
              leading: Icon(Icons.swap_horiz, color: colors.accent),
              title: const Text('调休：按某天课表上课'),
              subtitle: Text('例如周六补周一的课', style: muted),
              onTap: () => _pick(DayOverrideAction.actAs),
            ),
            ListTile(
              key: const ValueKey<String>('override-sheet-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑…'),
              subtitle: Text('停课、按某个星期或指定周次上课，可以写备注', style: muted),
              onTap: () => _pick(DayOverrideAction.edit),
            ),
            if (hasSetting)
              ListTile(
                key: const ValueKey<String>('override-sheet-clear'),
                leading: const Icon(Icons.restart_alt),
                title: const Text('清除设置'),
                subtitle: Text('恢复按原课表上课，可以撤销', style: muted),
                onTap: () => _pick(DayOverrideAction.clear),
              ),
          ],
        ),
      ),
    );
  }
}
