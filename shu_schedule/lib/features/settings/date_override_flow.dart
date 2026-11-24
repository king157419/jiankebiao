import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/schedule_utils.dart';
import 'date_override_editor.dart';

/// 添加 / 编辑某一天的调休、停课（v1.4.0 从 `TermSettingsPage` 抽出，
/// 学期设置页和周视图长按列头共用）。
///
/// - [date] 为 null：添加，编辑器里的日期默认今天；
/// - [date] 不为 null：编辑这一天（这一天还没有设置时就是「添加这一天」）。
///   保存时把日期改成了别的日子，会把 [date] 原来那条删掉；
/// - [initialMode]：预置编辑器的模式，例如周视图「调休：按某天课表上课」传
///   [OverrideMode.weekday]；null 时按已有设置还原（没有设置时是停课）。
///
/// 保存到的日期上已经有别的设置时先弹窗确认替换。返回键 / 取消什么都不改。
Future<void> editDateOverride(
  BuildContext context,
  AppState appState, {
  DateTime? date,
  OverrideMode? initialMode,
}) async {
  final config = appState.currentConfig;
  final now = DateTime.now();
  final initialDate = date ?? DateTime(now.year, now.month, now.day);
  final existing = date == null ? null : config.overrideOn(date);
  var initial = DateOverrideDraft.from(initialDate, existing);
  if (initialMode != null) initial = initial.copyWith(mode: initialMode);
  final draft = await Navigator.of(context).push<DateOverrideDraft>(
    MaterialPageRoute<DateOverrideDraft>(
      builder: (_) => DateOverrideEditorPage(
        initial: initial,
        totalWeeks: config.totalWeeks,
        editing: existing != null,
      ),
    ),
  );
  if (draft == null || !context.mounted) return;
  final latest = appState.currentConfig;
  final clash = latest.overrideOn(draft.date);
  final moved =
      date != null &&
      ScheduleUtils.dateKey(date) != ScheduleUtils.dateKey(draft.date);
  final movedOnto = clash != null && (date == null || moved);
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
  if (moved && latest.overrideOn(date) != null) {
    await appState.setDateOverride(date, null);
  }
  await appState.setDateOverride(draft.date, draft.toOverride());
}
