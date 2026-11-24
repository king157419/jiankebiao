import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_brand.dart';
import '../../core/app_state.dart';
import '../../core/holiday_repository.dart';
import '../../core/reminders/reminder_service.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/update_dialog.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../widgets/themed_background.dart';
import '../import/web/edu_session.dart';
import '../widgets/add_widget_helper.dart';
import 'about_page.dart';
import 'backup_sheet.dart';
import 'feedback_dialog.dart';
import 'ics_export_sheet.dart';
import 'periods_editor_page.dart';
import 'privacy_page.dart';
import 'reminder_settings_page.dart';
import 'term_settings_page.dart';
import 'theme_picker_page.dart';
import 'timetable_manage_page.dart';

/// 设置页「上课提醒」tile 的副标题（v1.4.0 修复轮）：开着时带上提醒跟随的课表名
/// （review-G P2-2）；通知权限没给时直说「没有通知权限」（P2-3 / P3-8）。
String reminderTileSubtitle(
  ReminderSettings settings, {
  String? timetableName,
  bool needsPermission = false,
}) {
  if (!settings.enabled) return '未开启';
  if (needsPermission) return '已开启 · 没有通知权限';
  final name = timetableName == null ? '' : ' · 跟随「$timetableName」';
  return '已开启 · 提前 ${settings.leadMinutes} 分钟$name';
}

/// 「桌面」组里「添加桌面小组件」的副标题（v1.5.0）。
const String settingsAddWidgetSubtitle = '把课表放到桌面上，不打开 App 也能看';

/// 「其他」组里「备份与恢复」的副标题（v1.5.0，D6）。
const String settingsBackupSubtitle = '换手机、重装前先导出一份';

/// 「其他」组里「隐私说明」的副标题（v1.5.0）。
const String settingsPrivacySubtitle = '课表只存在手机里；只在导入、检查更新、更新假期表时联网';

/// 设置页（v1.5.0 收敛成四组）：
/// - 课表：课表管理 / 学期设置 / 作息时间 / 上课提醒 / 导出到日历；
/// - 显示：显示非本周课程 / 格子里显示时间 / 主题；
/// - 桌面：添加桌面小组件；
/// - 其他：记住教务登录 / 备份与恢复 / 检查更新 / 关于 / 隐私说明 / 反馈。
///
/// v1.5.0 任务 A2：从周视图右上角的齿轮 `push` 进来，AppBar 自动带返回键
/// （颜色取 `AppBarTheme.foregroundColor` = `colors.headerText`，和标题、齿轮同色）。
class SettingsPage extends StatelessWidget {
  /// 检查更新用的 checker（测试注入）；null = 默认源 [UpdateChecker]。
  final UpdateChecker? updateChecker;

  /// 转发给子页（学期设置、课表管理）的假日表仓库和测试时钟。
  final HolidayRepository? holidayRepository;
  final DateTime Function()? clock;

  const SettingsPage({
    super.key,
    this.updateChecker,
    this.holidayRepository,
    this.clock,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final themeController = context.watch<ThemeController>();
    final theme = themeController.current;
    final config = appState.currentConfig;
    final checker = updateChecker ?? UpdateChecker();
    final lastCheck = appState.settings.lastUpdateCheck;
    final reminders = appState.settings.reminders;
    // 没有 Provider（只 pump 了设置页的测试）时为 null。
    final reminderService = context.watch<ReminderService?>();

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
              onTap: () => _push(context, TimetableManagePage(clock: clock)),
            ),
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('学期设置'),
              subtitle: Text(
                '${config.name} · ${config.totalWeeks} 周 · '
                '${config.showWeekend ? '显示周末' : '隐藏周末'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(
                context,
                TermSettingsPage(holidays: holidayRepository, clock: clock),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('作息时间'),
              subtitle: Text('共 ${config.periodCount} 节'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const PeriodsEditorPage()),
            ),
            ListTile(
              key: const ValueKey<String>('settings-reminders'),
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('上课提醒'),
              subtitle: Text(
                reminderTileSubtitle(
                  reminders,
                  timetableName: appState.currentTimetable?.name,
                  needsPermission:
                      reminderService?.needsPermissionFor(reminders) ?? false,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const ReminderSettingsPage()),
            ),
            ListTile(
              key: const ValueKey<String>('settings-export-ics'),
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('导出到日历（.ics）'),
              subtitle: const Text(
                '把当前课表生成日历文件，导入 iPhone / Outlook / Google 日历',
              ),
              enabled: appState.currentTimetable != null,
              onTap: appState.currentTimetable == null
                  ? null
                  : () => showIcsExportSheet(
                      context,
                      timetable: appState.currentTimetable!,
                    ),
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
              subtitle: Text(theme.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const ThemePickerPage()),
            ),
            const Divider(),
            _group(theme, '桌面'),
            ListTile(
              key: const ValueKey<String>('settings-add-widget'),
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('添加桌面小组件'),
              subtitle: const Text(settingsAddWidgetSubtitle),
              trailing: const Icon(Icons.add),
              onTap: () => showAddWidgetSheet(context),
            ),
            const Divider(),
            _group(theme, '其他'),
            SwitchListTile(
              key: const ValueKey<String>('settings-remember-login'),
              secondary: const Icon(Icons.key_outlined),
              title: const Text('记住教务登录'),
              subtitle: const Text('关闭时，导入完成或离开登录页后自动清除教务系统的登录信息'),
              value: appState.settings.rememberEduLogin,
              onChanged: (v) => _setRememberEduLogin(context, appState, v),
            ),
            ListTile(
              key: const ValueKey<String>('settings-backup'),
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('备份与恢复'),
              subtitle: const Text(settingsBackupSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openBackupAndRestore(context, appState),
            ),
            if (checker.isConfigured)
              ListTile(
                key: const ValueKey<String>('settings-check-update'),
                leading: const Icon(Icons.system_update_outlined),
                title: const Text('检查更新'),
                subtitle: Text(
                  lastCheck == null
                      ? '每天最多自动检查一次，有新版会提示'
                      : '上次检查：${_formatTime(lastCheck)}',
                ),
                onTap: () => runManualUpdateCheck(context, appState, checker),
              ),
            ListTile(
              key: const ValueKey<String>('settings-about'),
              leading: const Icon(Icons.info_outline),
              title: Text('关于${AppBrand.name}'),
              subtitle: const Text('v$appVersion · 无广告，数据仅存本地'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const AboutPage()),
            ),
            ListTile(
              key: const ValueKey<String>('settings-privacy'),
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('隐私说明'),
              subtitle: const Text(settingsPrivacySubtitle),
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
}
