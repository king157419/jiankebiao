import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/period_time.dart';
import 'period_form.dart';

/// 作息时间编辑：逐节改起止时间、末尾增删节次、一键恢复默认作息。
class PeriodsEditorPage extends StatelessWidget {
  const PeriodsEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final periods = List<PeriodTime>.from(appState.currentConfig.periods)
      ..sort((a, b) => a.index.compareTo(b.index));

    return Scaffold(
      appBar: AppBar(
        title: const Text('作息时间'),
        actions: <Widget>[
          TextButton(
            onPressed: () => _resetDefault(context, appState),
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '点击时间即可修改。结束时间必须晚于开始时间，且不能与相邻节次重叠。',
              style: TextStyle(
                fontSize: 12,
                color: theme.colors.onSurfaceMuted,
              ),
            ),
          ),
          for (var i = 0; i < periods.length; i++)
            ListTile(
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: theme.colors.surfaceVariant,
                child: Text(
                  '${periods[i].index}',
                  style: TextStyle(fontSize: 13, color: theme.colors.onSurface),
                ),
              ),
              title: Text('第 ${periods[i].index} 节'),
              subtitle: Text('${periods[i].start} - ${periods[i].end}'),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () => _edit(context, appState, periods, i),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await appState.updatePeriods(
                        PeriodForm.renumber(PeriodForm.appendPeriod(periods)),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('增加一节'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: periods.length <= 1
                        ? null
                        : () async {
                            await appState.updatePeriods(
                              PeriodForm.renumber(
                                PeriodForm.removeLast(periods),
                              ),
                            );
                          },
                    icon: const Icon(Icons.remove, size: 18),
                    label: const Text('删除末节'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    AppState appState,
    List<PeriodTime> periods,
    int position,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final period = periods[position];
    final start = await _pickTime(
      context,
      period.start,
      '第 ${period.index} 节开始',
    );
    if (start == null) return;
    if (!context.mounted) return;
    final end = await _pickTime(context, period.end, '第 ${period.index} 节结束');
    if (end == null) return;

    final error = PeriodForm.validateEdit(periods, position, start, end);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await appState.updatePeriods(
      PeriodForm.applyEdit(periods, position, start, end),
    );
  }

  Future<String?> _pickTime(
    BuildContext context,
    String initial,
    String help,
  ) async {
    final parts = initial.split(':');
    final picked = await showTimePicker(
      context: context,
      helpText: help,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      ),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _resetDefault(BuildContext context, AppState appState) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复默认作息'),
        content: const Text('将把作息表恢复为内置的每天 12 节示例作息，当前的自定义时间会丢失。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok == true) await appState.resetPeriodsToDefault();
  }
}
