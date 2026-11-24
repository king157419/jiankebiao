import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/schedule_utils.dart';
import '../../core/term_resolver.dart';
import '../../models/schedule_config.dart';

/// 「现在是第 [week] 周」时第 1 周的周一：[today] 所在周的周一往前推 `week - 1` 周。
DateTime firstMondayForWeek(DateTime today, int week) =>
    ScheduleUtils.addDays(ScheduleUtils.mondayOf(today), -(week - 1) * 7);

/// 面板的默认标题。
const String weekNumberSheetTitle = '现在是第几周？';

/// 手动新建课表时关掉周次面板后的提示文案。
const String unconfirmedTermStartHint = '开学日期还没定，点课表顶部的「第 N 周」可以校正';

/// 底部面板「现在是第几周？」（PLAN-1.5 D8）：选 1..[totalWeeks] 中的一个，
/// 返回第 1 周的周一；也可以点「我知道开学日期」直接选日期（返回那天所在周的周一）。
/// 关掉面板返回 null。
///
/// [upcomingStart] 非 null 时（开学前按校历导入），顶部多一行可选项
/// 「还没开学（9月14日开学）」，未给有效 [initialWeek] 时默认选中它，「确定」直接返回该日期。
///
/// [title] 不传时是 [weekNumberSheetTitle]；导入时按校历预选了周次，标题写成
/// 「按××大学校历，现在是第 4 周，对吗？」。
///
/// 导入预览页（「改」/「点这里选」/「确认导入」）、周视图「选择周次」底部的校正入口、
/// 学期设置页（「按当前周次设置」）与手动新建课表共用。
/// 只用 `Theme.of`，不依赖 `ThemeController`（导入预览页的测试里没有它）。
Future<DateTime?> showWeekNumberSheet(
  BuildContext context, {
  required DateTime today,
  required int totalWeeks,
  int? initialWeek,
  DateTime? upcomingStart,
  String? title,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => WeekNumberSheet(
      key: const ValueKey<String>('week-number-sheet'),
      today: today,
      totalWeeks: totalWeeks,
      initialWeek: initialWeek,
      upcomingStart: upcomingStart,
      title: title,
    ),
  );
}

/// 手动新建课表前问「现在是第几周？」（PLAN-1.5 R1-2）：
/// - 选了周次或开学日期 → 用该日期建表并写入 `AppSettings.termStartConfirmed`，返回 true；
/// - 关掉面板 → 仍然建表（`startDate = mondayOf(today)`），不写 `termStartConfirmed`，
///   [showSnackBarOnDismiss] 为 true 时弹 [unconfirmedTermStartHint]，返回 false。
Future<bool> createTimetableWithWeekPrompt(
  BuildContext context,
  AppState appState, {
  String name = '我的课表',
  required DateTime today,
  int totalWeeks = 18,
  bool showSnackBarOnDismiss = true,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final picked = await showWeekNumberSheet(
    context,
    today: today,
    totalWeeks: totalWeeks,
  );
  final confirmed = picked != null;
  final startDate = picked ?? ScheduleUtils.mondayOf(today);
  await appState.createTimetable(
    name: name,
    config: ScheduleConfig(
      name: name,
      startDate: startDate,
      totalWeeks: totalWeeks,
    ),
    confirmTermStart: confirmed,
    today: today,
  );
  if (!confirmed && showSnackBarOnDismiss) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: ValueKey<String>('term-start-unconfirmed'),
          content: Text(unconfirmedTermStartHint),
        ),
      );
  }
  return confirmed;
}

/// 「本周不是第 N 周？点这里校正」（周视图）/「按当前周次设置」（学期设置）：
/// 弹 [showWeekNumberSheet]（预选按当前开学日期算出的周次），选好后改当前课表的
/// 开学日期并写入 `termStartConfirmed`，SnackBar「已把本周设为第 x 周」。返回新的开学日期；
/// 没有课表或关掉面板返回 null。
Future<DateTime?> correctCurrentWeek(
  BuildContext context, {
  required DateTime today,
}) async {
  final appState = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final timetable = appState.currentTimetable;
  if (timetable == null) return null;
  final config = timetable.config;
  final picked = await showWeekNumberSheet(
    context,
    today: today,
    totalWeeks: config.totalWeeks,
    initialWeek: ScheduleUtils.rawWeekOf(today, config),
  );
  if (picked == null) return null;
  await appState.updateConfig(
    timetable.config.copyWith(startDate: picked),
    timetableId: timetable.id,
    confirmTermStart: true,
  );
  final week = weekNumberOn(picked, today);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey<String>('week-corrected'),
        content: Text(
          week >= 1 && week <= config.totalWeeks
              ? '已把本周设为第 $week 周'
              : '已把开学日期设为 ${monthDayText(picked)}',
        ),
      ),
    );
  return picked;
}

/// [showWeekNumberSheet] 的面板内容。
class WeekNumberSheet extends StatefulWidget {
  final DateTime today;
  final int totalWeeks;

  /// 预先选中的周次；不在 1..[totalWeeks] 里时不预选。
  final int? initialWeek;

  /// 开学前导入时校历给出的开学日期（第 1 周周一）；非 null 时顶部显示「还没开学（…）」选项。
  final DateTime? upcomingStart;

  /// 标题；null = [weekNumberSheetTitle]。
  final String? title;

  const WeekNumberSheet({
    super.key,
    required this.today,
    required this.totalWeeks,
    this.initialWeek,
    this.upcomingStart,
    this.title,
  });

  @override
  State<WeekNumberSheet> createState() => _WeekNumberSheetState();
}

class _WeekNumberSheetState extends State<WeekNumberSheet> {
  int? _week;
  bool _selectedUpcoming = false;

  int get _total => widget.totalWeeks < 1 ? 1 : widget.totalWeeks;

  DateTime? get _upcomingMonday => widget.upcomingStart == null
      ? null
      : ScheduleUtils.mondayOf(widget.upcomingStart!);

  @override
  void initState() {
    super.initState();
    final w = widget.initialWeek;
    if (w != null && w >= 1 && w <= _total) {
      _week = w;
      _selectedUpcoming = false;
    } else if (widget.upcomingStart != null) {
      _week = null;
      _selectedUpcoming = true;
    } else {
      _week = null;
      _selectedUpcoming = false;
    }
  }

  DateTime? get _selectedMonday {
    if (_selectedUpcoming) return _upcomingMonday;
    final week = _week;
    return week == null ? null : firstMondayForWeek(widget.today, week);
  }

  Future<void> _pickDate() async {
    final initial = _selectedMonday ?? widget.today;
    final first = DateTime(2020);
    final last = DateTime(2035, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
      helpText: '选择开学日期（第 1 周的任意一天）',
    );
    if (picked == null || !mounted) return;
    Navigator.of(context).pop(ScheduleUtils.mondayOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final week = _week;
    final upcomingMonday = _upcomingMonday;
    final monday = _selectedMonday;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Padding(
        // 底部留出手势条 / 导航栏的位置（useSafeArea 只管顶部）。
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.title ?? weekNumberSheetTitle,
              key: const ValueKey<String>('week-number-title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '选好后会自动算出开学日期',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (upcomingMonday != null) ...<Widget>[
                      ChoiceChip(
                        key: const ValueKey<String>('week-number-upcoming'),
                        label: Text('还没开学（${monthDayText(upcomingMonday)}开学）'),
                        selected: _selectedUpcoming,
                        onSelected: (_) => setState(() {
                          _selectedUpcoming = true;
                          _week = null;
                        }),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (var w = 1; w <= _total; w++)
                          ChoiceChip(
                            key: ValueKey<String>('week-number-$w'),
                            label: Text('$w'),
                            selected: !_selectedUpcoming && w == week,
                            onSelected: (_) => setState(() {
                              _selectedUpcoming = false;
                              _week = w;
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              monday == null ? '选一个周次' : '将把 ${monthDayText(monday)}（周一）设为第一周',
              key: const ValueKey<String>('week-number-preview'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: monday == null ? muted : null,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton(
                  key: const ValueKey<String>('week-number-pick-date'),
                  onPressed: _pickDate,
                  child: const Text('我知道开学日期'),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey<String>('week-number-confirm'),
                  onPressed: monday == null
                      ? null
                      : () => Navigator.of(context).pop(monday),
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
