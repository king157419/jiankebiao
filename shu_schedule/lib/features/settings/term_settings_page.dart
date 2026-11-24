import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/holiday_presets.dart';
import '../../core/holiday_repository.dart';
import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../core/term_resolver.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/schedule_config.dart';
import '../import/adapters/school_registry.dart';
import 'date_override_editor.dart';
import 'date_override_flow.dart';
import 'holiday_apply_page.dart';
import 'week_number_sheet.dart';

/// 学期设置：学期名、开学日期（含「按当前周次设置」）、总周数、显示周末、
/// 调休 / 停课、学校校历。
///
/// v1.5.0（PLAN-1.5 D8）：开学日期下面多一行「按当前周次设置」（key `term-set-by-week`）；
/// 原来的「一键套用预设」（内置示例学期）换成「学校校历」：只在当前课表有 `schoolId`、
/// 且这所学校有校历（`holidays.json` 的学校学期 ∪ `schools.json` 的 `termPresets`）时显示。
class TermSettingsPage extends StatefulWidget {
  /// 读学校校历用的假日表仓库（测试注入）；不传时用默认仓库。课表没有 `schoolId` 时不读。
  final HolidayRepository? holidays;

  /// 测试用时钟（「按当前周次设置」的「今天」）；不传时用 [DateTime.now]。
  final DateTime Function()? clock;

  const TermSettingsPage({super.key, this.holidays, this.clock});

  @override
  State<TermSettingsPage> createState() => _TermSettingsPageState();
}

class _TermSettingsPageState extends State<TermSettingsPage> {
  /// 正在读 / 已经读好的假日表，以及它是给哪所学校读的。
  Future<HolidayPresets>? _holidays;
  String? _holidaysFor;

  /// [schoolId] 的假日表（只读一次；换了学校再读）。没有 `schoolId` 返回 null。
  Future<HolidayPresets>? _holidaysOf(String? schoolId) {
    if (schoolId == null) return null;
    if (_holidaysFor != schoolId || _holidays == null) {
      _holidaysFor = schoolId;
      _holidays = _load();
    }
    return _holidays;
  }

  Future<HolidayPresets> _load() async {
    try {
      return await (widget.holidays ?? HolidayRepository()).load();
    } catch (_) {
      return HolidayPresets.empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final config = appState.currentConfig;
    final hasTimetable = appState.currentTimetable != null;
    final schoolId = appState.currentTimetable?.schoolId;
    final today = (widget.clock ?? DateTime.now)();

    return Scaffold(
      appBar: AppBar(title: const Text('学期设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          if (!hasTimetable)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '还没有课表，请先在「课表管理」里新建一张。',
                style: TextStyle(fontSize: 13, color: theme.colors.danger),
              ),
            ),
          ListTile(
            title: const Text('学期名'),
            subtitle: Text(config.name),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            enabled: hasTimetable,
            onTap: () => _editName(context, appState, config),
          ),
          ListTile(
            title: const Text('开学日期'),
            subtitle: Text(_formatStartDate(config.startDate)),
            trailing: const Icon(Icons.calendar_today_outlined, size: 18),
            enabled: hasTimetable,
            onTap: () => _pickStartDate(context, appState, config),
          ),
          ListTile(
            key: const ValueKey<String>('term-set-by-week'),
            title: const Text('按当前周次设置'),
            subtitle: Text(_byWeekSubtitle(config, today, hasTimetable)),
            trailing: const Icon(Icons.chevron_right),
            enabled: hasTimetable,
            onTap: () => correctCurrentWeek(context, today: today),
          ),
          FutureBuilder<HolidayPresets>(
            future: _holidaysOf(schoolId),
            builder: (context, snapshot) {
              final presets = snapshot.data;
              if (schoolId == null || presets == null) {
                return const SizedBox.shrink();
              }
              final school = SchoolRegistry.byId(schoolId);
              final terms = schoolCalendarTerms(
                schoolId: schoolId,
                presets: presets,
                schoolPresets: school?.termPresets,
              );
              if (terms.isEmpty) return const SizedBox.shrink();
              final schoolName =
                  presets.schools[schoolId]?.name ?? school?.name ?? '学校';
              return Column(
                key: const ValueKey<String>('term-school-calendar'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '$schoolName校历',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.headerText,
                      ),
                    ),
                  ),
                  for (final term in terms)
                    ListTile(
                      key: ValueKey<String>(
                        'term-calendar-${ScheduleUtils.dateKey(term.startDate)}',
                      ),
                      title: Text(term.name),
                      subtitle: Text(
                        '${_formatDate(term.startDate)} 开学 · '
                        '${term.totalWeeks} 周',
                      ),
                      trailing:
                          ScheduleUtils.daysBetween(
                                term.startDate,
                                config.startDate,
                              ) ==
                              0
                          ? Icon(Icons.check, color: theme.colors.accent)
                          : const Icon(Icons.chevron_right),
                      enabled: hasTimetable,
                      onTap: () => _applySchoolTerm(
                        context,
                        appState,
                        config,
                        terms,
                        term,
                        today,
                      ),
                    ),
                  const Divider(),
                ],
              );
            },
          ),
          ListTile(
            title: const Text('总周数'),
            subtitle: Text('${config.totalWeeks} 周'),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            enabled: hasTimetable,
            onTap: () => _editTotalWeeks(context, appState, config),
          ),
          SwitchListTile(
            title: const Text('显示周末'),
            subtitle: const Text('关闭后只显示周一到周五；某周的周六、周日有课或有调休时，那一天照样显示'),
            value: config.showWeekend,
            onChanged: hasTimetable
                ? (v) async {
                    await appState.updateConfig(
                      config.copyWith(showWeekend: v),
                    );
                  }
                : null,
          ),
          const Divider(),
          ..._overrideSection(context, appState, config, hasTimetable),
        ],
      ),
    );
  }

  static String _byWeekSubtitle(
    ScheduleConfig config,
    DateTime today,
    bool hasTimetable,
  ) {
    if (!hasTimetable) return '选「现在是第几周」，自动算出开学日期';
    final rawWeek = ScheduleUtils.rawWeekOf(today, config);
    if (rawWeek < 1) return '还没开学；不对就点这里改';
    if (rawWeek > config.totalWeeks) return '本学期已结束；不对就点这里改';
    return '现在是第 $rawWeek 周；不对就点这里改';
  }

  static bool _isDefaultTermName(String name, List<CalendarTerm> terms) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return true;
    const defaults = <String>{'我的课表', '默认学期', '未命名学期', '导入的课表'};
    if (defaults.contains(trimmed)) return true;
    if (exampleTermPresets.any((p) => p.name == trimmed)) return true;
    if (terms.any((t) => t.name == trimmed)) return true;
    return false;
  }

  Future<void> _applySchoolTerm(
    BuildContext context,
    AppState appState,
    ScheduleConfig config,
    List<CalendarTerm> terms,
    CalendarTerm term,
    DateTime today,
  ) async {
    final tt = appState.currentTimetable;
    if (tt == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final id = tt.id;
    final previousConfig = config;
    final previousConfirmed = appState.settings.termStartConfirmed[id];
    final nextName = _isDefaultTermName(config.name, terms)
        ? term.name
        : config.name;
    await appState.updateConfig(
      config.copyWith(
        name: nextName,
        startDate: term.startDate,
        totalWeeks: term.totalWeeks,
      ),
      timetableId: id,
      confirmTermStart: true,
    );
    final week = weekNumberOn(term.startDate, today);
    final status = week < 1
        ? '还没开学'
        : (week > term.totalWeeks ? '本学期已结束' : '现在第 $week 周');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey<String>('term-school-calendar-applied'),
          content: Text('已按校历设为 ${monthDayText(term.startDate)}开学（$status）'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => appState.restoreTimetableConfig(
              id,
              previousConfig,
              previousConfirmedStart: previousConfirmed,
            ),
          ),
        ),
      );
  }

  // ------------------------------------------------------------ 调休 / 停课

  List<Widget> _overrideSection(
    BuildContext context,
    AppState appState,
    ScheduleConfig config,
    bool hasTimetable,
  ) {
    final theme = context.read<ThemeController>().current;
    final keys = config.overrides.keys.toList()..sort();
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          '调休 / 停课',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.colors.headerText,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          '放假停课、节假日调休（例如「周六上周一的课」）在这里按日期设置，'
          '周课表和桌面小组件会一起按调整后的课显示。',
          style: TextStyle(fontSize: 12, color: theme.colors.onSurfaceMuted),
        ),
      ),
      for (final key in keys)
        if (ScheduleConfig.parseDate(key) case final date?)
          ListTile(
            key: ValueKey<String>('override-item-$key'),
            leading: Icon(
              config.overrides[key]!.cancelled
                  ? Icons.event_busy_outlined
                  : Icons.swap_horiz,
              color: config.overrides[key]!.cancelled
                  ? theme.colors.danger
                  : theme.colors.accent,
            ),
            title: Text(formatOverrideDate(date)),
            subtitle: Text(
              <String>[
                describeDateOverride(config.overrides[key]!),
                ?config.overrides[key]!.note,
              ].join(' · '),
            ),
            enabled: hasTimetable,
            onTap: () => editDateOverride(context, appState, date: date),
            trailing: IconButton(
              key: ValueKey<String>('override-delete-$key'),
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: hasTimetable
                  ? () => _deleteOverride(context, appState, date)
                  : null,
            ),
          ),
      ListTile(
        key: const ValueKey<String>('override-apply-holidays'),
        leading: const Icon(Icons.auto_awesome_outlined),
        title: const Text('套用节假日安排'),
        subtitle: const Text('内置国家假期表和已收录学校的放假 / 补课通知'),
        trailing: const Icon(Icons.chevron_right),
        enabled: hasTimetable,
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const HolidayApplyPage()),
        ),
      ),
      ListTile(
        key: const ValueKey<String>('override-add'),
        leading: const Icon(Icons.add),
        title: const Text('添加调休 / 停课'),
        enabled: hasTimetable,
        onTap: () => editDateOverride(context, appState),
      ),
    ];
  }

  Future<void> _deleteOverride(
    BuildContext context,
    AppState appState,
    DateTime date,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final previous = appState.currentConfig.overrideOn(date);
    await appState.setDateOverride(date, null);
    if (previous == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已删除 ${formatOverrideDate(date)} 的设置'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => appState.setDateOverride(date, previous),
          ),
        ),
      );
  }

  Future<void> _editName(
    BuildContext context,
    AppState appState,
    ScheduleConfig config,
  ) async {
    final value = await _promptText(context, '学期名', config.name);
    if (value == null || value.trim().isEmpty) return;
    await appState.updateConfig(config.copyWith(name: value.trim()));
  }

  Future<void> _editTotalWeeks(
    BuildContext context,
    AppState appState,
    ScheduleConfig config,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final value = await _promptText(
      context,
      '总周数（1-30）',
      '${config.totalWeeks}',
      keyboardType: TextInputType.number,
    );
    if (value == null) return;
    final weeks = int.tryParse(value.trim());
    if (weeks == null || weeks < 1 || weeks > 30) {
      messenger.showSnackBar(const SnackBar(content: Text('总周数必须是 1-30 的整数')));
      return;
    }
    await appState.updateConfig(config.copyWith(totalWeeks: weeks));
  }

  Future<void> _pickStartDate(
    BuildContext context,
    AppState appState,
    ScheduleConfig config,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: config.startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '选择开学日期',
    );
    if (picked == null) return;
    await appState.updateConfig(
      config.copyWith(startDate: picked),
      confirmTermStart: true,
    );
    final aligned = ScheduleConfig(
      name: config.name,
      startDate: picked,
    ).startDate;
    if (ScheduleUtils.daysBetween(aligned, picked) != 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('已自动对齐到当周周一：${_formatStartDate(aligned)}')),
      );
    }
  }

  static Future<String?> _promptText(
    BuildContext context,
    String title,
    String initial, {
    TextInputType? keyboardType,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  static String _formatStartDate(DateTime d) =>
      '${monthDayText(d)}（${weekdayNamesCn[d.weekday]}）';

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
