import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_brand.dart';
import '../../core/app_state.dart';
import '../../core/storage.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/update_dialog.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../widgets/themed_background.dart';
import '../import/web/edu_session.dart';
import '../widgets/add_widget_helper.dart';
import 'about_page.dart';
import 'backup_service.dart';
import 'feedback_dialog.dart';
import 'periods_editor_page.dart';
import 'privacy_page.dart';
import 'term_settings_page.dart';
import 'theme_picker_page.dart';
import 'timetable_manage_page.dart';

/// 设置页：分组列表。
class SettingsPage extends StatelessWidget {
  /// 检查更新用的 checker（测试注入）；null = 默认源 [UpdateChecker]。
  final UpdateChecker? updateChecker;

  const SettingsPage({super.key, this.updateChecker});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final themeController = context.watch<ThemeController>();
    final theme = themeController.current;
    final config = appState.currentConfig;
    final checker = updateChecker ?? UpdateChecker();
    final lastCheck = appState.settings.lastUpdateCheck;

    return ThemedBackground(
      theme: theme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('设置'),
          backgroundColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            if (appState.warnings.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colors.surface,
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  border: Border.all(color: theme.colors.danger),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '读取数据时发现问题',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.danger,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final w in appState.warnings)
                      Text(
                        w,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colors.onSurfaceMuted,
                        ),
                      ),
                  ],
                ),
              ),
            _group(theme, '桌面小组件'),
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('添加桌面小组件'),
              subtitle: const Text('直接弹出系统确认框，不用在桌面里翻找'),
              trailing: const Icon(Icons.add),
              onTap: () => requestAddWidget(context),
            ),
            const Divider(),
            _group(theme, '课表'),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('课表管理'),
              subtitle: Text(
                appState.currentTimetable == null
                    ? '还没有课表'
                    : '当前：${appState.currentTimetable!.name}'
                          '（共 ${appState.timetables.length} 张）',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const TimetableManagePage()),
            ),
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('学期设置'),
              subtitle: Text(
                '${config.name} · ${config.totalWeeks} 周 · '
                '${config.showWeekend ? '显示周末' : '隐藏周末'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const TermSettingsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('作息时间'),
              subtitle: Text('共 ${config.periodCount} 节'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const PeriodsEditorPage()),
            ),
            const Divider(),
            _group(theme, '显示'),
            SwitchListTile(
              secondary: const Icon(Icons.blur_on_outlined),
              title: const Text('显示非本周课程'),
              subtitle: const Text('以半透明形式显示这一周不上的课'),
              value: appState.settings.showNonCurrentWeekCourses,
              onChanged: appState.setShowNonCurrentWeekCourses,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.access_time),
              title: const Text('格子里显示时间'),
              subtitle: const Text('在课程块里附上上课时刻'),
              value: appState.settings.showTimeInGrid,
              onChanged: appState.setShowTimeInGrid,
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('主题'),
              subtitle: Text('${theme.name} · ${theme.description}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const ThemePickerPage()),
            ),
            const Divider(),
            _group(theme, '教务导入'),
            SwitchListTile(
              secondary: const Icon(Icons.key_outlined),
              title: const Text('记住教务登录'),
              subtitle: const Text('关闭时，导入完成或离开登录页后自动清除教务系统的登录信息'),
              value: appState.settings.rememberEduLogin,
              onChanged: (v) => _setRememberEduLogin(context, appState, v),
            ),
            const Divider(),
            _group(theme, '备份'),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('导出备份'),
              subtitle: const Text('生成 JSON 文件并通过系统分享保存'),
              onTap: () => _export(context, appState),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('导入备份'),
              subtitle: const Text('从 JSON 文件恢复或合并课表'),
              onTap: () => _import(context, appState),
            ),
            ListTile(
              key: const ValueKey<String>('settings-import-timetable'),
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('从文件导入课表'),
              subtitle: const Text('同学「分享此课表」发来的文件，新建一张课表，不影响现有数据'),
              onTap: () => importTimetableFromFile(context, appState),
            ),
            const Divider(),
            _group(theme, '关于'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text('关于${AppBrand.name}'),
              subtitle: const Text('v$appVersion · 无广告，数据仅存本地'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const AboutPage()),
            ),
            ListTile(
              key: const ValueKey<String>('settings-check-update'),
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('检查更新'),
              subtitle: Text(
                !checker.isConfigured
                    ? '未配置更新源'
                    : (lastCheck == null
                          ? '每天最多自动检查一次，有新版会提示'
                          : '上次检查：${_formatTime(lastCheck)}'),
              ),
              enabled: checker.isConfigured,
              onTap: () => runManualUpdateCheck(context, appState, checker),
            ),
            ListTile(
              key: const ValueKey<String>('settings-privacy'),
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('隐私说明'),
              subtitle: const Text('不收集、不上传；只在导入课表和检查更新时联网'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const PrivacyPage()),
            ),
            ListTile(
              key: const ValueKey<String>('settings-feedback'),
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('反馈'),
              subtitle: const Text('提问题、提建议，可复制诊断信息'),
              onTap: () => showFeedbackDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(AppTheme theme, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: theme.colors.headerText,
      ),
    ),
  );

  static String _formatTime(DateTime t) =>
      '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// 关掉「记住教务登录」时立刻清一次已保存的登录态。
  Future<void> _setRememberEduLogin(
    BuildContext context,
    AppState appState,
    bool value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await appState.setRememberEduLogin(value);
    if (value) return;
    final result = await clearEduSessionIfNeeded(
      rememberLogin: false,
      event: EduSessionEvent.rememberTurnedOff,
      store: WebViewEduSessionStore(),
    );
    if (result == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.ok ? '已清除保存的教务登录信息' : '部分登录信息没能清除，下次导入完成后会再清一次'),
      ),
    );
  }

  Future<void> _export(BuildContext context, AppState appState) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BackupService.exportAndShare(appState);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _import(BuildContext context, AppState appState) async {
    final messenger = ScaffoldMessenger.of(context);
    StorageSnapshot? snapshot;
    try {
      snapshot = await BackupService.pickAndParse();
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('备份文件不合法：${e.message}')));
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('读取失败：$e')));
      return;
    }
    if (snapshot == null) return;
    if (!context.mounted) return;

    final mode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入备份'),
        content: Text(
          '备份里有 ${snapshot!.timetables.length} 张课表。\n'
          '「覆盖」会用备份完全替换现有数据；「合并」保留现有课表并把备份追加进来。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('merge'),
            child: const Text('合并'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('replace'),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
    if (mode == null) return;
    if (mode == 'replace') {
      await appState.restoreFrom(snapshot);
      messenger.showSnackBar(const SnackBar(content: Text('已用备份覆盖全部数据')));
    } else {
      final added = await BackupService.mergeInto(appState, snapshot);
      messenger.showSnackBar(SnackBar(content: Text('已合并 $added 张课表')));
    }
  }
}
