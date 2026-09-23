import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/schedule_config.dart';
import 'date_override_editor.dart';

/// 学期设置：学期名、开学日期、总周数、显示周末、调休 / 停课、一键套用预设。
class TermSettingsPage extends StatelessWidget {
  const TermSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final config = appState.currentConfig;
    final hasTimetable = appState.currentTimetable != null;

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
            title: const Text('开学日期（第 1 周周一）'),
            subtitle: Text(_formatDate(config.startDate)),
            trailing: const Icon(Icons.calendar_today_outlined, size: 18),
            enabled: hasTimetable,
            onTap: () => _pickStartDate(context, appState, config),
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
            subtitle: const Text('关闭后课表只显示周一到周五'),
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
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '一键套用预设',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colors.headerText,
              ),
            ),
          ),
          for (final preset in exampleTermPresets)
            ListTile(
              title: Text(preset.name),
              subtitle: Text(
                '${_formatDate(preset.startDate)} 开学 · ${preset.totalWeeks} 周',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: hasTimetable,
              onTap: () async {
                await appState.updateConfig(
                  config.copyWith(
                    name: preset.name,
                    startDate: preset.startDate,
                    totalWeeks: preset.totalWeeks,
                  ),
                );
              },
            ),
        ],
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
          '周课表、今日页和桌面小组件会一起按调整后的课显示。',
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
            onTap: () => _editOverride(context, appState, config, date: date),
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
        key: const ValueKey<String>('override-add'),
        leading: const Icon(Icons.add),
        title: const Text('添加调休 / 停课'),
        enabled: hasTimetable,
        onTap: () => _editOverride(context, appState, config),
      ),
    ];
  }

  /// 添加（[date] 为 null）或编辑一条调休。编辑时改了日期会把旧日期那条删掉。
  Future<void> _editOverride(
    BuildContext context,
    AppState appState,
    ScheduleConfig config, {
    DateTime? date,
  }) async {
    final now = DateTime.now();
    final initialDate = date ?? DateTime(now.year, now.month, now.day);
    final draft = await Navigator.of(context).push<DateOverrideDraft>(
      MaterialPageRoute<DateOverrideDraft>(
        builder: (_) => DateOverrideEditorPage(
          initial: DateOverrideDraft.from(
            initialDate,
            date == null ? null : config.overrideOn(date),
          ),
          totalWeeks: config.totalWeeks,
          editing: date != null,
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    final latest = appState.currentConfig;
    final clash = latest.overrideOn(draft.date);
    final movedOnto =
        clash != null &&
        (date == null ||
            ScheduleUtils.dateKey(date) != ScheduleUtils.dateKey(draft.date));
    if (movedOnto) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('这一天已经有设置'),
          content: Text(
            '${formatOverrideDate(draft.date)} 已设置为「${describeDateOverride(clash)}」，要替换吗？',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('替换'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (date != null &&
        ScheduleUtils.dateKey(date) != ScheduleUtils.dateKey(draft.date)) {
      await appState.setDateOverride(date, null);
    }
    await appState.setDateOverride(draft.date, draft.toOverride());
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
    await appState.updateConfig(config.copyWith(startDate: picked));
    final aligned = ScheduleConfig(
      name: config.name,
      startDate: picked,
    ).startDate;
    if (ScheduleUtils.daysBetween(aligned, picked) != 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('已自动对齐到当周周一：${_formatDate(aligned)}')),
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

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
