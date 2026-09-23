import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/timetable.dart';
import 'timetable_share.dart';

/// 课表管理：切换、新建、重命名、删除（不能删掉最后一张）、
/// 分享单张课表、从文件导入课表。
class TimetableManagePage extends StatelessWidget {
  const TimetableManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final timetables = appState.timetables;
    final currentId = appState.currentTimetable?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('课表管理'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('import-timetable-file'),
            tooltip: '从文件导入课表',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: () => importTimetableFromFile(context, appState),
          ),
        ],
      ),
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
                    '${tt.config.name} · ${tt.courses.length} 门课 · '
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
                      } else if (v == 'share') {
                        _share(context, tt);
                      } else if (v == 'delete') {
                        _delete(context, appState, tt);
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'share',
                        child: Text('分享此课表'),
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

  Future<void> _share(BuildContext context, Timetable tt) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await TimetableShare.share(tt);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('分享失败：$e')));
    }
  }

  Future<void> _create(BuildContext context, AppState appState) async {
    final name = await _promptText(context, '新建课表', '我的课表');
    if (name == null || name.trim().isEmpty) return;
    await appState.createTimetable(name: name.trim());
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
        content: Text('确定删除「${tt.name}」及其 ${tt.courses.length} 门课吗？不可撤销。'),
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

/// 「从文件导入课表」：选 JSON → 校验 → 新建（不会覆盖现有课表）。
///
/// 课表管理页右上角和设置页「备份」分组都走这里。
Future<void> importTimetableFromFile(
  BuildContext context,
  AppState appState,
) async {
  final messenger = ScaffoldMessenger.of(context);
  TimetableImportOutcome? outcome;
  try {
    outcome = await TimetableShare.pickAndImport(appState);
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('这不是有效的课表文件：${e.message}')));
    return;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('读取失败：$e')));
    return;
  }
  if (outcome == null) return;
  final names = outcome.created.map((t) => '「${t.name}」').join('、');
  final courses = outcome.created.fold<int>(
    0,
    (sum, t) => sum + t.courses.length,
  );
  final warn = outcome.warnings.isEmpty
      ? ''
      : '（${outcome.warnings.length} 条提醒：${outcome.warnings.first}）';
  messenger.showSnackBar(
    SnackBar(content: Text('已导入$names，共 $courses 门课，已切换过去$warn')),
  );
}
