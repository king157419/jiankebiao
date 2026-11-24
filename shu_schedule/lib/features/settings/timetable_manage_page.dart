import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/timetable.dart';
import 'ics_export_sheet.dart';
import 'week_number_sheet.dart';

/// 课表管理：切换、新建、重命名、删除（不能删掉最后一张）、导出到日历（.ics）。
///
/// v1.5.0 删掉了「分享此课表」和右上角的「从文件导入课表」（D5）；
/// 整份数据的导出 / 恢复在设置 →「备份与恢复」。
class TimetableManagePage extends StatelessWidget {
  /// 测试用时钟（「新建课表」弹周次面板的「今天」）；不传时用 [DateTime.now]。
  final DateTime Function()? clock;

  const TimetableManagePage({super.key, this.clock});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final timetables = appState.timetables;
    final currentId = appState.currentTimetable?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('课表管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, appState),
        icon: const Icon(Icons.add),
        label: const Text('新建课表'),
      ),
      body: timetables.isEmpty
          ? Center(
              child: Text(
                '还没有课表，点右下角新建一张。',
                style: TextStyle(color: theme.colors.onSurfaceMuted),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: timetables.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final tt = timetables[i];
                final selected = tt.id == currentId;
                return ListTile(
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? theme.colors.primary
                        : theme.colors.outline,
                  ),
                  title: Text(tt.name),
                  subtitle: Text(
                    '${tt.config.name} · ${tt.courseCountText} · '
                    '${tt.config.totalWeeks} 周',
                  ),
                  onTap: () async {
                    await appState.switchTimetable(tt.id);
                  },
                  trailing: PopupMenuButton<String>(
                    key: ValueKey<String>('timetable-menu-${tt.id}'),
                    onSelected: (v) {
                      if (v == 'rename') {
                        _rename(context, appState, tt);
                      } else if (v == 'ics') {
                        showIcsExportSheet(context, timetable: tt);
                      } else if (v == 'delete') {
                        _delete(context, appState, tt);
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'ics',
                        child: Text('导出到日历（.ics）'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'rename',
                        child: Text('重命名'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        enabled: timetables.length > 1,
                        child: Text(
                          timetables.length > 1 ? '删除' : '删除（至少保留一张）',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _create(BuildContext context, AppState appState) async {
    final name = await _promptText(context, '新建课表', '我的课表');
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await createTimetableWithWeekPrompt(
      context,
      appState,
      name: name.trim(),
      today: (clock ?? DateTime.now)(),
    );
  }

  Future<void> _rename(
    BuildContext context,
    AppState appState,
    Timetable tt,
  ) async {
    final name = await _promptText(context, '重命名课表', tt.name);
    if (name == null || name.trim().isEmpty) return;
    await appState.renameTimetable(tt.id, name.trim());
  }

  Future<void> _delete(
    BuildContext context,
    AppState appState,
    Timetable tt,
  ) async {
    if (appState.timetables.length <= 1) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除课表'),
        content: Text('确定删除「${tt.name}」及其 ${tt.courseCountText}吗？不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await appState.deleteTimetable(tt.id);
  }

  static Future<String?> _promptText(
    BuildContext context,
    String title,
    String initial,
  ) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
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
}
