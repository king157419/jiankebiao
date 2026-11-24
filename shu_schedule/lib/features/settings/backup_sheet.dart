import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_brand.dart';
import '../../core/app_state.dart';
import '../../core/storage.dart';
import '../../core/theme/theme_controller.dart';
import 'backup_service.dart';

/// 「备份与恢复」面板里的两个动作（v1.5.0，D6）。
enum BackupAction { export, restore }

/// 恢复时的两种方式。
enum _RestoreMode { merge, replace }

/// 选到的文件不是备份时的提示（不把解析错误原样给用户看）。
const String backupNotBackupText = '这不是${AppBrand.name}的备份文件';

/// 文件读不出来时的提示。
const String backupUnreadableText = '没能读取这个文件';

/// 只弹面板，返回用户选的动作；点空白处关掉返回 null。
Future<BackupAction?> showBackupSheet(BuildContext context) {
  return showModalBottomSheet<BackupAction>(
    context: context,
    builder: (_) => const _BackupSheet(),
  );
}

/// 设置 →「备份与恢复」：先弹面板，再用调用方的 [context] 执行选中的动作。
///
/// 面板关掉以后它自己的 context 就失效了，所以导出、选文件、合并 / 覆盖确认
/// 都放在面板外面做。[clock] 只决定导出文件名里的时间（测试注入）。
Future<void> openBackupAndRestore(
  BuildContext context,
  AppState appState, {
  DateTime Function()? clock,
}) async {
  final action = await showBackupSheet(context);
  if (action == null || !context.mounted) return;
  switch (action) {
    case BackupAction.export:
      await exportBackup(context, appState, now: clock?.call());
    case BackupAction.restore:
      await restoreBackup(context, appState);
  }
}

/// 导出备份文件并调起系统分享。
Future<void> exportBackup(
  BuildContext context,
  AppState appState, {
  DateTime? now,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await BackupService.exportAndShare(appState, now: now);
  } catch (e) {
    debugPrint('[backup] 导出失败：$e');
    messenger.showSnackBar(const SnackBar(content: Text('没能导出备份，请再试一次')));
  }
}

/// 从备份文件恢复：选文件 → 校验 → 问「合并」还是「覆盖」。
Future<void> restoreBackup(BuildContext context, AppState appState) async {
  final messenger = ScaffoldMessenger.of(context);
  StorageSnapshot? snapshot;
  try {
    snapshot = await BackupService.pickAndParse();
  } on FormatException catch (e) {
    debugPrint('[backup] 不是备份文件：$e');
    messenger.showSnackBar(const SnackBar(content: Text(backupNotBackupText)));
    return;
  } catch (e) {
    debugPrint('[backup] 读取失败：$e');
    messenger.showSnackBar(const SnackBar(content: Text(backupUnreadableText)));
    return;
  }
  if (snapshot == null || !context.mounted) return;

  final count = snapshot.timetables.length;
  final mode = await showDialog<_RestoreMode>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey<String>('backup-restore-dialog'),
      title: const Text('从备份恢复'),
      content: Text(
        '备份里有 $count 张课表。\n'
        '「覆盖」会用备份完全替换现有数据；「合并」保留现有课表并把备份追加进来。',
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('backup-restore-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey<String>('backup-restore-replace'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () =>
              Navigator.of(dialogContext).pop(_RestoreMode.replace),
          child: const Text('覆盖'),
        ),
        FilledButton(
          key: const ValueKey<String>('backup-restore-merge'),
          onPressed: () => Navigator.of(dialogContext).pop(_RestoreMode.merge),
          child: const Text('合并'),
        ),
      ],
    ),
  );
  if (mode == null) return;
  switch (mode) {
    case _RestoreMode.replace:
      await appState.restoreFrom(snapshot);
      messenger.showSnackBar(const SnackBar(content: Text('已用备份覆盖全部数据')));
    case _RestoreMode.merge:
      final added = await BackupService.mergeInto(appState, snapshot);
      messenger.showSnackBar(SnackBar(content: Text('已合并 $added 张课表')));
  }
}

class _BackupSheet extends StatelessWidget {
  const _BackupSheet();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>().current;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey<String>('backup-sheet'),
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '备份与恢复',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '课表只存在这台手机里。换手机、重装或卸载前，先导出一份发到微信或网盘。',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colors.onSurfaceMuted,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const ValueKey<String>('backup-export'),
              leading: const Icon(Icons.ios_share),
              title: const Text('导出备份文件'),
              subtitle: const Text('所有课表和设置存成一个文件，用微信、网盘等发给自己保存'),
              onTap: () => Navigator.of(context).pop(BackupAction.export),
            ),
            ListTile(
              key: const ValueKey<String>('backup-restore'),
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('从备份文件恢复'),
              subtitle: const Text('选之前导出的文件，可以合并进来，也可以整个覆盖'),
              onTap: () => Navigator.of(context).pop(BackupAction.restore),
            ),
          ],
        ),
      ),
    );
  }
}
