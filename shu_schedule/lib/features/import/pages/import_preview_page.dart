import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/holiday_presets.dart';
import '../../../core/presets.dart';
import '../../../core/schedule_utils.dart';
import '../../../core/term_resolver.dart';
import '../../../models/course.dart';
import '../../../models/period_time.dart';
import '../../../models/schedule_config.dart';
import '../../../models/timetable.dart';
import '../../settings/week_number_sheet.dart';
import '../adapters/school_adapter.dart';
import '../diagnostics/diagnostic_sample.dart';

/// 导入方式。
enum ImportMode {
  /// 覆盖当前课表的课程与学期设置（保留主题等）。
  overwrite,

  /// 新建一张课表并切换过去。
  createNew,
}

/// 预览页里「作息从哪来」。
enum PeriodSource {
  /// 教务系统页面里识别出来的。
  detected,

  /// 沿用当前课表的作息。
  current,

  /// 内置模板（`periodTemplates`）。
  template,
}

/// 预览页选中的一套作息。
class PeriodChoice {
  final PeriodSource source;
  final List<PeriodTime> periods;

  /// [PeriodSource.template] 时是哪套模板。
  final PeriodTemplate? template;

  const PeriodChoice._(this.source, this.periods, {this.template});

  factory PeriodChoice.detected(List<PeriodTime> periods) =>
      PeriodChoice._(PeriodSource.detected, List.unmodifiable(periods));

  factory PeriodChoice.current(List<PeriodTime> periods) =>
      PeriodChoice._(PeriodSource.current, List.unmodifiable(periods));

  factory PeriodChoice.template(PeriodTemplate t) =>
      PeriodChoice._(PeriodSource.template, t.periods, template: t);

  /// 界面上的一行说明。
  String get label {
    switch (source) {
      case PeriodSource.detected:
        return '教务系统识别（${periods.length} 节）';
      case PeriodSource.current:
        return '沿用当前课表作息（${periods.length} 节）';
      case PeriodSource.template:
        return '模板：${template!.name}';
    }
  }

  bool sameAs(PeriodChoice other) =>
      source == other.source && template?.id == other.template?.id;
}

/// 预览页的默认值（纯函数，有单测）。
class ImportPreviewDefaults {
  ImportPreviewDefaults._();

  /// 作息：`detectedPeriods ?? 当前课表作息 ?? 模板`（模板按学校的
  /// `periodProfileId` 选，找不到用第一套）。
  static PeriodChoice periods({
    List<PeriodTime>? detected,
    List<PeriodTime>? current,
    String? periodProfileId,
  }) {
    if (detected != null && detected.isNotEmpty) {
      return PeriodChoice.detected(detected);
    }
    if (current != null && current.isNotEmpty) {
      return PeriodChoice.current(current);
    }
    return PeriodChoice.template(periodTemplateById(periodProfileId));
  }
}

/// 导入流程第三步：预览并确认。
///
/// v1.5.0（PLAN-1.5 D8）：开学日期按 [resolveTermStart] 定——教务识别到周次就直接用；
/// 否则学校校历里有「今天」所在的学期就用它当默认值（「按××大学校历 · 9月14日开学 ·
/// 现在第 4 周」），点「确认导入」时再弹一次「现在是第几周？」面板（预选校历推出的周次）；
/// 都没有就弹同一个面板、不预选，不选不能导入。不再默认「今天所在的周是第一周」。
/// 导入成功、退回首页后请首页弹一次校历建议面板（`AppState.requestCalendarPrompt`）。
class ImportPreviewPage extends StatefulWidget {
  const ImportPreviewPage({
    super.key,
    required this.result,
    required this.schoolName,
    this.adapter,
    this.diagnostics,
    this.onImported,
    this.today,
    this.holidayPresets,
  });

  final ImportResult result;
  final String schoolName;

  /// 学校适配器：提供 `schools.json` 里的学期预设（校历来源之一）和作息模板 id，可空。
  final SchoolAdapter? adapter;

  /// 诊断样本原料；非 null 时右上角显示「导出导入记录」。
  final DiagnosticInput? diagnostics;

  /// 课表写入成功、退回首页之前调用（清理教务登录态）。失败不影响导入。
  final Future<void> Function()? onImported;

  /// 「今天」，测试用；默认 `DateTime.now()`。
  final DateTime? today;

  /// 当前的假日表（`holidays.json` 里的学校校历）。由打开本页的一方先读好传进来，
  /// 页面里不做 IO；null 当作空表。
  final HolidayPresets? holidayPresets;

  @override
  State<ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends State<ImportPreviewPage> {
  late final DateTime _today;

  /// 学校 id（`r.schoolId ?? widget.adapter?.id`），解析校历和写入课表共用同一个来源。
  late final String? _schoolId;

  /// 进页面时推出来的开学日期和来源（[resolveTermStart]）。
  late final TermResolution _resolution;

  /// 第 1 周周一；来源未知且用户还没选时为 null。
  DateTime? _startDate;

  /// 用户在面板里选过周次（「改」/「点这里选」/ 确认时的面板）。选过就直接导入。
  bool _manual = false;
  late int _totalWeeks;
  late String _name;
  late Set<String> _selected;
  late PeriodChoice _periodChoice;
  ImportMode _mode = ImportMode.overwrite;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final r = widget.result;
    _today = widget.today ?? DateTime.now();
    _schoolId = r.schoolId ?? widget.adapter?.id;
    _resolution = resolveTermStart(
      detectedStart: r.detectedStartDate,
      detectedWeek: r.detectedCurrentWeek,
      schoolId: _schoolId,
      presets: widget.holidayPresets ?? HolidayPresets.empty,
      schoolPresets: widget.adapter?.presets,
      schoolName: widget.schoolName,
      today: _today,
    );
    _startDate = _resolution.startDate;
    _totalWeeks = (_resolution.totalWeeks ?? 18).clamp(
      _minTotalWeeks,
      _maxTotalWeeks,
    );
    _name = r.termName ?? r.rawTermName ?? '导入的课表';
    _selected = r.courses.map((c) => c.id).toSet();
    _periodChoice = ImportPreviewDefaults.periods(
      detected: r.detectedPeriods,
      current: _currentPeriods(),
      periodProfileId: widget.adapter?.periodProfileId,
    );
  }

  List<PeriodTime>? _currentPeriods() {
    try {
      return context.read<AppState>().currentTimetable?.config.periods;
    } catch (_) {
      return null;
    }
  }

  List<Course> get _selectedCourses =>
      widget.result.courses.where((c) => _selected.contains(c.id)).toList();

  /// 总周数下拉框的取值范围（和 [_buildSummaryCard] 里的 items 保持一致）。
  static const int _minTotalWeeks = 10;
  static const int _maxTotalWeeks = 30;

  /// 解析出的课程里出现过的最大周次。
  int get _maxCourseWeek {
    var max = 0;
    for (final c in widget.result.courses) {
      for (final w in c.weeks) {
        if (w > max) max = w;
      }
    }
    return max;
  }

  /// 解析出的课程里用到的最大节次。
  int get _maxCoursePeriod {
    var max = 0;
    for (final c in widget.result.courses) {
      if (c.endPeriod > max) max = c.endPeriod;
    }
    return max;
  }

  // ------------------------------------------------------------------ 交互

  /// 现在的开学日期下，「今天」是第几周；还没定开学日期时为 null。
  int? get _currentWeek {
    final start = _startDate;
    return start == null ? null : weekNumberOn(start, _today);
  }

  /// 「按××大学校历」里的学校名。
  String get _schoolLabel => _resolution.schoolName ?? widget.schoolName;

  /// 「开学日期」一行的「改」/「点这里选」：弹「现在是第几周？」面板，选了就算手动选过。
  Future<void> _pickWeek() async {
    final picked = await showWeekNumberSheet(
      context,
      today: _today,
      totalWeeks: _totalWeeks,
      initialWeek: _currentWeek,
      upcomingStart: _resolution.upcoming ? _resolution.startDate : null,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = picked;
      _manual = true;
    });
  }

  /// 点「确认导入」时：开学日期是教务识别的、或用户手动选过 → 直接过；
  /// 按校历推的（学期内）→ 弹面板预选校历周次，标题「按××大学校历，现在是第 4 周，对吗？」；
  /// 按校历推的（开学前）→ 弹面板默认选中「还没开学」，标题「按××大学校历，9月14日开学，对吗？」；
  /// 不知道 → 弹面板不预选。关掉面板 = 不导入，留在预览页。
  Future<bool> _ensureStartDate() async {
    if (_manual || _resolution.source == TermStartSource.detected) {
      return _startDate != null;
    }
    if (_resolution.source == TermStartSource.schoolCalendar &&
        _resolution.upcoming &&
        _resolution.startDate != null) {
      final upcomingStart = _resolution.startDate!;
      final picked = await showWeekNumberSheet(
        context,
        today: _today,
        totalWeeks: _totalWeeks,
        upcomingStart: upcomingStart,
        title: '按$_schoolLabel校历，${monthDayText(upcomingStart)}开学，对吗？',
      );
      if (picked == null || !mounted) return false;
      setState(() {
        _startDate = picked;
        _manual = true;
      });
      return true;
    }
    final week = _currentWeek;
    final calendar =
        _resolution.source == TermStartSource.schoolCalendar && week != null;
    final picked = await showWeekNumberSheet(
      context,
      today: _today,
      totalWeeks: _totalWeeks,
      initialWeek: calendar ? week : null,
      title: calendar ? '按$_schoolLabel校历，现在是第 $week 周，对吗？' : null,
    );
    if (picked == null || !mounted) return false;
    setState(() {
      _startDate = picked;
      _manual = true;
    });
    return true;
  }

  Future<void> _pickPeriods() async {
    final options = <PeriodChoice>[
      if (widget.result.detectedPeriods?.isNotEmpty ?? false)
        PeriodChoice.detected(widget.result.detectedPeriods!),
      if (_currentPeriods()?.isNotEmpty ?? false)
        PeriodChoice.current(_currentPeriods()!),
      for (final t in periodTemplates) PeriodChoice.template(t),
    ];
    final picked = await showDialog<PeriodChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('作息时间'),
        children: <Widget>[
          for (final o in options)
            ListTile(
              leading: Icon(
                o.sameAs(_periodChoice)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(o.label),
              subtitle: Text(_periodSummary(o)),
              onTap: () => Navigator.of(ctx).pop(o),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _periodChoice = picked);
  }

  static String _periodSummary(PeriodChoice c) {
    if (c.source == PeriodSource.template) return c.template!.description;
    if (c.periods.isEmpty) return '';
    return '${c.periods.first.start} 开始 · ${c.periods.last.end} 结束';
  }

  Future<void> _confirm() async {
    final courses = _selectedCourses;
    if (courses.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请至少选择一门课程')));
      return;
    }
    if (!await _ensureStartDate() || !mounted) return;
    final startDate = _startDate!;
    setState(() => _busy = true);
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final r = widget.result;
    final periods = List<PeriodTime>.from(_periodChoice.periods);

    final String importedId;
    try {
      // 没有课表时只能新建（build 里也会把单选框锁在「新建」上）。
      final current = appState.currentTimetable;
      final overwrite = _mode == ImportMode.overwrite && current != null;
      final imported = await appState.applyImport(
        overwriteId: overwrite ? current.id : null,
        name: _name,
        courses: courses,
        config: overwrite
            ? current.config.copyWith(
                name: _name,
                startDate: startDate,
                totalWeeks: _totalWeeks,
                periods: periods,
              )
            : ScheduleConfig(
                name: _name,
                startDate: startDate,
                totalWeeks: _totalWeeks,
                periods: periods,
              ),
        schoolId: _schoolId,
        systemType: r.systemType,
        termCode: r.termCode,
        importedAt: DateTime.now(),
        confirmTermStart:
            _manual || _resolution.source == TermStartSource.detected,
      );
      importedId = imported.id;
    } catch (e) {
      debugPrint('保存课表失败：$e');
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(const SnackBar(content: Text('保存课表失败，请重试')));
      return;
    }

    // 课表已经写进去了；清理登录态失败不能影响「导入成功」。
    try {
      await widget.onImported?.call();
    } catch (_) {}

    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      SnackBar(content: Text('已导入 ${Timetable.formatCourseCount(courses)}')),
    );
    // 首页下一帧弹校历建议面板（PLAN-1.5 D9 触发点 (a)）。
    appState.requestCalendarPrompt(importedId);
  }

  Future<void> _exportDiagnostics() async {
    final input = widget.diagnostics;
    if (input == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DiagnosticSample.exportAndShare(input);
    } catch (e) {
      debugPrint('导出导入记录失败：$e');
      messenger.showSnackBar(const SnackBar(content: Text('导出导入记录失败，请稍后再试')));
    }
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.result;
    final hasCurrent = context.select<AppState, bool>(
      (s) => s.currentTimetable != null,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('确认导入'),
        actions: <Widget>[
          if (widget.diagnostics != null)
            IconButton(
              tooltip: '导出导入记录',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: _busy ? null : _exportDiagnostics,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
        children: <Widget>[
          _buildSummaryCard(theme, r),
          if (r.warnings.isNotEmpty) _buildWarnings(theme, r.warnings),
          if (r.unscheduled.isNotEmpty) _buildUnscheduled(theme, r.unscheduled),
          _buildModeSelector(theme, hasCurrent: hasCurrent),
          _buildCourseHeader(theme),
          ...r.courses.map((c) => _buildCourseTile(theme, c)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '确认导入（${Timetable.uniqueCourseCount(_selectedCourses)} 门）',
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme, ImportResult r) {
    final subtitle = <String>[
      widget.schoolName,
      if (r.studentName != null) r.studentName!,
      if (r.rawTermName != null) r.rawTermName!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: <Widget>[
          ListTile(
            title: Text(_name, style: theme.textTheme.titleMedium),
            subtitle: Text(subtitle),
            trailing: IconButton(
              tooltip: '重命名',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _renameTerm,
            ),
          ),
          const Divider(height: 1),
          _buildStartDateTile(theme),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('总周数'),
            trailing: DropdownButton<int>(
              value: _totalWeeks,
              underline: const SizedBox.shrink(),
              items: List<DropdownMenuItem<int>>.generate(
                _maxTotalWeeks - _minTotalWeeks + 1,
                (i) => DropdownMenuItem<int>(
                  value: i + _minTotalWeeks,
                  child: Text('${i + _minTotalWeeks} 周'),
                ),
              ),
              onChanged: (v) {
                if (v != null) setState(() => _totalWeeks = v);
              },
            ),
          ),
          if (_maxCourseWeek > _totalWeeks) _buildWeekOverflowHint(theme),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('作息时间'),
            subtitle: Text(_periodChoice.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickPeriods,
          ),
          if (_maxCoursePeriod > _periodChoice.periods.length)
            _buildPeriodOverflowHint(theme),
        ],
      ),
    );
  }

  /// 「开学日期」一行（D8）：
  /// - 教务识别：「9月14日（周一）　教务系统显示当前第 3 周」+「改」；
  /// - 按校历：「按××大学校历 · 9月14日开学 · 现在第 4 周」+「改」；
  /// - 手动选过：「9月14日开学 · 现在第 4 周 · 已手动选择」+「改」；
  /// - 不知道：「还没确定 · 点这里选」。
  Widget _buildStartDateTile(ThemeData theme) {
    final start = _startDate;
    final week = _currentWeek;
    final String text;
    if (start == null) {
      text = _resolution.label;
    } else if (_manual) {
      text = <String>[
        '${monthDayText(start)}开学',
        if (week != null && week >= 1) '现在第 $week 周',
        '已手动选择',
      ].join(' · ');
    } else if (_resolution.source == TermStartSource.detected) {
      text =
          '${monthDayText(start)}（${weekdayNamesCn[start.weekday]}）　'
          '${_resolution.label}';
    } else {
      text = _resolution.label;
    }
    return ListTile(
      key: const ValueKey<String>('import-start-date'),
      leading: const Icon(Icons.event),
      title: const Text('开学日期'),
      subtitle: Text(
        text,
        key: const ValueKey<String>('import-start-date-text'),
        style: start == null ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      trailing: start == null
          ? const Icon(Icons.chevron_right)
          : TextButton(
              key: const ValueKey<String>('import-start-date-change'),
              onPressed: _pickWeek,
              child: const Text('改'),
            ),
      onTap: _pickWeek,
    );
  }

  /// 课程周次超出总周数时的提示。
  ///
  /// 不提示的话，超出部分的课导入后在课表里永远不显示，用户只会觉得「导入丢课了」。
  Widget _buildWeekOverflowHint(ThemeData theme) {
    final suggested = _maxCourseWeek.clamp(_minTotalWeeks, _maxTotalWeeks);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '课程里最大周次是第 $_maxCourseWeek 周，超过了总周数 $_totalWeeks 周，'
              '第 ${_totalWeeks + 1} 周及以后的课导入后不会显示。',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _totalWeeks = suggested),
            child: Text('改为 $suggested 周'),
          ),
        ],
      ),
    );
  }

  /// 课程用到的节次超出所选作息时的提示。
  Widget _buildPeriodOverflowHint(ThemeData theme) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '课程用到了第 $_maxCoursePeriod 节，但所选作息只有 '
              '${_periodChoice.periods.length} 节，多出的节次没有时间。'
              '可以换一套作息，或导入后在「作息时间」里补上。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameTerm() async {
    final controller = TextEditingController(text: _name);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('课表名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    setState(() => _name = value);
  }

  Widget _buildWarnings(ThemeData theme, List<String> warnings) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.warning_amber_rounded),
        title: Text('${warnings.length} 条提醒'),
        subtitle: const Text('点开看看有没有课被跳过'),
        children: warnings
            .map(
              (w) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('· '),
                    Expanded(child: Text(w, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildUnscheduled(ThemeData theme, List<Course> list) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.pending_actions_outlined),
        title: Text('${list.length} 门没有固定时间的课'),
        subtitle: const Text('不会写入课表网格，可稍后手动添加'),
        children: list
            .map(
              (c) => ListTile(
                dense: true,
                title: Text(c.name),
                subtitle: Text(
                  <String>[
                    if (c.teacher != null) c.teacher!,
                    if (c.location != null) c.location!,
                    if (c.note != null) c.note!,
                  ].join(' · '),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildModeSelector(ThemeData theme, {required bool hasCurrent}) {
    // 没有课表时强制显示「新建」，但不在 build 里改 state（改 state 要走 _confirm）。
    final shown = hasCurrent ? _mode : ImportMode.createNew;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: RadioGroup<ImportMode>(
        groupValue: shown,
        onChanged: (v) => setState(() => _mode = v ?? _mode),
        child: Column(
          children: <Widget>[
            RadioListTile<ImportMode>(
              value: ImportMode.overwrite,
              enabled: hasCurrent,
              title: const Text('覆盖当前课表'),
              subtitle: Text(
                hasCurrent ? '替换现有课程与学期设置，保留课表名称与主题' : '当前还没有课表，只能新建',
              ),
            ),
            RadioListTile<ImportMode>(
              value: ImportMode.createNew,
              title: const Text('新建课表'),
              subtitle: Text('名称：$_name'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseHeader(ThemeData theme) {
    final all = widget.result.courses.length;
    final allSelected = _selected.length == all && all > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '课程（已选 ${_selected.length} / $all）',
              style: theme.textTheme.titleSmall,
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _selected = allSelected
                  ? <String>{}
                  : widget.result.courses.map((c) => c.id).toSet();
            }),
            child: Text(allSelected ? '全不选' : '全选'),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseTile(ThemeData theme, Course c) {
    final periodText = '${c.startPeriod}-${c.endPeriod}节';
    final detail = <String>[
      weekdayNamesCn[c.day.clamp(1, 7)],
      periodText,
      ScheduleUtils.formatWeeksText(c.weeks),
      if (c.location != null) c.location!,
      if (c.teacher != null) c.teacher!,
    ].where((s) => s.isNotEmpty).join(' · ');

    return CheckboxListTile(
      value: _selected.contains(c.id),
      onChanged: (v) => setState(() {
        if (v == true) {
          _selected.add(c.id);
        } else {
          _selected.remove(c.id);
        }
      }),
      title: Text(c.name),
      subtitle: Text(detail, style: theme.textTheme.bodySmall),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
    );
  }
}
