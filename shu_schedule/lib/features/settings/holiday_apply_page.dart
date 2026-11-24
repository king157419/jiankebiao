import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/holiday_presets.dart';
import '../../core/holiday_repository.dart';
import '../../core/schedule_utils.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/update/update_dialog.dart'
    show launchExternally, refreshHolidaysQuietly;
import '../../models/schedule_config.dart';
import 'date_override_editor.dart';

/// 「套用节假日安排」：按国家假日表 / 已收录学校的通知，一次勾选写入多条调休 / 停课（v1.3.1）。
///
/// v1.4.0：数据来自 [HolidayRepository]（内置 + 联网更新的缓存，取较新的一份）。
/// 页面头部显示数据版本（「假期表 · 内置 2026-10-06」/「假期表 · 已更新 …」），
/// 右上角刷新按钮强制联网更新；进入页面时静默做一次非强制刷新（24 小时节流），
/// 更新成功就重新读取。
class HolidayApplyPage extends StatefulWidget {
  /// 测试注入的固定数据；null = 从 [repository] 读。
  final HolidayPresets? presets;

  /// 数据来源（测试注入）；null = 默认的 [HolidayRepository]。
  ///
  /// 只注入了 [presets]、没注入它时，页面不做进入时的静默刷新（老测试不联网、不碰磁盘）。
  final HolidayRepository? repository;

  const HolidayApplyPage({super.key, this.presets, this.repository});

  @override
  State<HolidayApplyPage> createState() => _HolidayApplyPageState();
}

class _HolidayApplyPageState extends State<HolidayApplyPage> {
  HolidayPresets? _presets;

  late final HolidayRepository _repository =
      widget.repository ?? HolidayRepository();

  /// 用户手动改过的勾选（key = yyyy-MM-dd）；没改过的按 [_defaultChecked]。
  final Map<String, bool> _choice = <String, bool>{};
  bool _applying = false;

  /// 正在手动刷新（按钮转圈、禁用）。
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _presets = widget.presets;
    if (_presets == null) {
      _reload().then((_) => _silentRefresh());
    } else if (widget.repository != null) {
      _silentRefresh();
    }
  }

  Future<void> _reload() async {
    final value = await _repository.load();
    if (mounted) setState(() => _presets = value);
  }

  /// 进入页面时的非强制刷新：节流 / 未配置 / 失败都不打扰用户，更新成功才重新读取。
  Future<void> _silentRefresh() async {
    if (!mounted) return;
    final result = await refreshHolidaysQuietly(
      _repository,
      context.read<AppState>(),
    );
    if (!mounted || result == null || !result.isUpdated) return;
    await _reload();
  }

  /// 右上角刷新按钮：强制联网，用 SnackBar 告诉用户结果。
  Future<void> _manualRefresh() async {
    if (_refreshing) return;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    setState(() => _refreshing = true);
    HolidayRefreshResult? result;
    try {
      result = await _repository.refreshFor(appState, force: true);
      if (result.isUpdated) await _reload();
    } catch (e) {
      debugPrint('刷新假期表异常：$e');
      result = null;
    }
    if (!mounted) return;
    setState(() => _refreshing = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(describeHolidayRefresh(result))));
  }

  PreferredSizeWidget _appBar() => AppBar(
    title: const Text('套用节假日安排'),
    actions: <Widget>[
      if (_repository.repo.isConfigured)
        IconButton(
          key: const ValueKey<String>('holiday-refresh'),
          tooltip: '联网更新假期表',
          onPressed: _refreshing ? null : _manualRefresh,
          icon: _refreshing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
    ],
  );

  Widget _dataVersion(HolidayPresets presets, Color color) => Text(
    holidayDataVersionText(presets),
    key: const ValueKey<String>('holiday-data-version'),
    style: TextStyle(fontSize: 12, color: color),
  );

  static bool _defaultChecked(HolidaySuggestion s) =>
      s.applicable && !s.conflicts;

  bool _checked(HolidaySuggestion s) {
    if (!s.applicable) return false;
    return _choice[ScheduleUtils.dateKey(s.date)] ?? _defaultChecked(s);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final presets = _presets;
    final timetable = appState.currentTimetable;

    if (presets == null) {
      return Scaffold(
        appBar: _appBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final plan = timetable == null
        ? const HolidayPlan(title: '', sourceText: '', items: [])
        : presets.planFor(
            config: timetable.config,
            schoolId: timetable.schoolId,
          );
    final selected = plan.items.where(_checked).toList();
    final count = selected.length;

    if (plan.isEmpty) {
      return Scaffold(
        appBar: _appBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _dataVersion(presets, theme.colors.onSurfaceMuted),
                const SizedBox(height: 12),
                Text(
                  '没有找到适用于当前学期的节假日安排',
                  key: const ValueKey<String>('holiday-empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '假期表目前只收录了部分年份和学校。可以返回上一页，'
                  '用「添加调休 / 停课」按学校通知手动设置'
                  '${_repository.repo.isConfigured ? '，也可以点右上角联网更新假期表' : ''}。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _appBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _dataVersion(presets, theme.colors.onSurfaceMuted),
          ),
          _header(context, plan),
          for (final s in plan.items) _row(context, s),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const ValueKey<String>('holiday-apply'),
            onPressed: count == 0 || _applying
                ? null
                : () => _apply(context, appState, selected),
            child: Text('套用 $count 条'),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, HolidayPlan plan) {
    final theme = context.read<ThemeController>().current;
    final url = plan.sourceUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colors.surfaceVariant,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                plan.title,
                key: const ValueKey<String>('holiday-plan-title'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '来源：${plan.sourceText}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colors.onSurfaceMuted,
                ),
              ),
              if (url != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey<String>('holiday-source'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _openSource(context, url),
                    child: const Text('查看来源'),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '以学校教务通知为准；运动会、考试周等校内安排不在其中，套用后仍可逐条修改或删除。',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, HolidaySuggestion s) {
    final theme = context.read<ThemeController>().current;
    final key = ScheduleUtils.dateKey(s.date);
    final muted = TextStyle(fontSize: 13, color: theme.colors.onSurfaceMuted);
    final danger = TextStyle(fontSize: 12, color: theme.colors.danger);

    final override = s.override;
    if (s.needsConfirmation || override == null) {
      final existing = s.existing;
      return ListTile(
        key: ValueKey<String>('holiday-item-$key'),
        leading: Icon(Icons.info_outline, color: theme.colors.accent),
        title: Text(formatOverrideDate(s.date)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(s.note ?? '需要按学校通知手动设置', style: muted),
            if (existing != null)
              Text(
                '当前设置：${_describe(existing)}',
                style: TextStyle(fontSize: 12, color: theme.colors.accent),
              ),
          ],
        ),
      );
    }

    final lines = <Widget>[
      Text(
        <String>[describeDateOverride(override), ?s.note].join(' · '),
        style: muted,
      ),
      if (s.conflicts && s.existing != null)
        Text('将覆盖：${_describe(s.existing!)}', style: danger),
      if (s.warning != null) Text(s.warning!, style: danger),
    ];

    return CheckboxListTile(
      key: ValueKey<String>('holiday-item-$key'),
      controlAffinity: ListTileControlAffinity.leading,
      value: s.alreadyApplied ? true : _checked(s),
      onChanged: s.alreadyApplied
          ? null
          : (v) => setState(() => _choice[key] = v ?? false),
      title: Text(formatOverrideDate(s.date)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
      secondary: s.alreadyApplied
          ? Text(
              '已设置',
              style: TextStyle(
                fontSize: 12,
                color: theme.colors.onSurfaceMuted,
              ),
            )
          : null,
    );
  }

  static String _describe(DateOverride o) =>
      <String>[describeDateOverride(o), ?o.note].join(' · ');

  Future<void> _apply(
    BuildContext context,
    AppState appState,
    List<HolidaySuggestion> selected,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _applying = true);
    final values = <DateTime, DateOverride>{
      for (final s in selected) s.date: s.override!,
    };
    await appState.applyDateOverrides(values);
    if (!mounted) return;
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已套用 ${values.length} 条调休 / 停课')));
  }

  Future<void> _openSource(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    final ok = uri != null && await launchExternally(uri);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('打不开链接：$url')));
    }
  }
}

/// 页面头部的数据版本：「假期表 · 内置 2026-10-06」/「假期表 · 已更新 2026-11-02」。
String holidayDataVersionText(HolidayPresets presets) {
  final date = presets.updatedAtText;
  final label = presets.source == HolidayDataSource.remote ? '已更新' : '内置';
  return date == null ? '假期表 · $label' : '假期表 · $label $date';
}

/// 刷新结果给用户看的一句话（SnackBar）。[result] 为 null 表示刷新过程抛了异常。
String describeHolidayRefresh(HolidayRefreshResult? result) {
  if (result == null) return '假期表这次没更新成功，稍后会再试';
  switch (result.status) {
    case HolidayRefreshStatus.notConfigured:
      return '更新源未配置';
    case HolidayRefreshStatus.throttled:
      return '24 小时内已经更新过假期表';
    case HolidayRefreshStatus.updated:
      final date = result.presets?.updatedAtText;
      return date == null ? '假期表已更新' : '假期表已更新（$date）';
    case HolidayRefreshStatus.unchanged:
      return '假期表已是最新';
    case HolidayRefreshStatus.failed:
      if (result.errors.isNotEmpty) {
        debugPrint('假期表刷新失败：${result.errors.join('；')}');
      }
      return '假期表这次没更新成功，稍后会再试';
  }
}
