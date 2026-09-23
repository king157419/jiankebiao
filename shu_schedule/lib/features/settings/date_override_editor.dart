import 'package:flutter/material.dart';

import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../models/schedule_config.dart';

/// 调休编辑器的三种模式（PLAN-1.3 Phase C.4：停课 / 按某个星期上课 / 指定周次）。
enum OverrideMode {
  /// 这一天停课。
  cancelled,

  /// 按某个星期的课上（可再指定周次）。
  weekday,

  /// 按某一周的课上（可再指定星期）。
  week,
}

/// 编辑中的一条调休（纯数据，方便单测）。
class DateOverrideDraft {
  final DateTime date;
  final OverrideMode mode;

  /// 按星期几上课；[OverrideMode.weekday] 必填，[OverrideMode.week] 可选。
  final int? weekday;

  /// 按第几周上课；[OverrideMode.week] 必填，[OverrideMode.weekday] 可选。
  final int? week;
  final String note;

  const DateOverrideDraft({
    required this.date,
    this.mode = OverrideMode.cancelled,
    this.weekday,
    this.week,
    this.note = '',
  });

  /// 从已有规则还原（编辑）。两个 actAs 都有时按「按某个星期上课」模式展示。
  factory DateOverrideDraft.from(DateTime date, DateOverride? o) {
    if (o == null) return DateOverrideDraft(date: date);
    final OverrideMode mode;
    if (o.cancelled) {
      mode = OverrideMode.cancelled;
    } else if (o.actAsWeekday != null) {
      mode = OverrideMode.weekday;
    } else if (o.actAsWeek != null) {
      mode = OverrideMode.week;
    } else {
      mode = OverrideMode.cancelled;
    }
    return DateOverrideDraft(
      date: date,
      mode: mode,
      weekday: o.actAsWeekday,
      week: o.actAsWeek,
      note: o.note ?? '',
    );
  }

  DateOverrideDraft copyWith({
    DateTime? date,
    OverrideMode? mode,
    int? weekday,
    int? week,
    String? note,
    bool clearWeekday = false,
    bool clearWeek = false,
  }) => DateOverrideDraft(
    date: date ?? this.date,
    mode: mode ?? this.mode,
    weekday: clearWeekday ? null : (weekday ?? this.weekday),
    week: clearWeek ? null : (week ?? this.week),
    note: note ?? this.note,
  );

  /// 校验：返回第一条错误，没问题返回 null。
  String? validate() {
    switch (mode) {
      case OverrideMode.cancelled:
        return null;
      case OverrideMode.weekday:
        if (weekday == null) return '请选择按星期几的课上';
      case OverrideMode.week:
        if (week == null) return '请选择按第几周的课上';
    }
    return null;
  }

  /// 转成要存的规则（调用前先 [validate]）。停课模式下忽略星期 / 周次。
  DateOverride toOverride() {
    final trimmed = note.trim();
    final n = trimmed.isEmpty ? null : trimmed;
    if (mode == OverrideMode.cancelled) return DateOverride.cancelled(note: n);
    return DateOverride.actAs(week: week, weekday: weekday, note: n);
  }
}

/// 列表里一条调休的说明文字（不含备注）：
/// 「停课」/「按第 5 周周一上课」/「按周一的课上」/「按第 5 周的课上（星期不变）」。
String describeDateOverride(DateOverride o) {
  if (o.cancelled) return '停课';
  final week = o.actAsWeek;
  final weekday = o.actAsWeekday;
  if (week != null && weekday != null) {
    return '按第 $week 周${weekdayNamesCn[weekday]}上课';
  }
  if (weekday != null) return '按${weekdayNamesCn[weekday]}的课上';
  if (week != null) return '按第 $week 周的课上（星期不变）';
  return '只有备注';
}

/// `2026-10-10 周六`。
String formatOverrideDate(DateTime d) =>
    '${ScheduleUtils.dateKey(d)} ${weekdayNamesCn[d.weekday]}';

/// 调休 / 停课编辑页。保存时 pop 出 [DateOverrideDraft]，返回键 pop null。
class DateOverrideEditorPage extends StatefulWidget {
  final DateOverrideDraft initial;
  final int totalWeeks;

  /// 是否是编辑已有的一条（决定标题）。
  final bool editing;

  const DateOverrideEditorPage({
    super.key,
    required this.initial,
    required this.totalWeeks,
    this.editing = false,
  });

  @override
  State<DateOverrideEditorPage> createState() => _DateOverrideEditorPageState();
}

class _DateOverrideEditorPageState extends State<DateOverrideEditorPage> {
  late DateOverrideDraft _draft;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _note = TextEditingController(text: _draft.note);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _weeks => widget.totalWeeks < 1 ? 1 : widget.totalWeeks;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final current = _draft.copyWith(note: _note.text);
    final preview = current.validate() == null
        ? describeDateOverride(current.toOverride())
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing ? '编辑调休 / 停课' : '添加调休 / 停课'),
        actions: <Widget>[
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          ListTile(
            key: const ValueKey<String>('override-date'),
            contentPadding: EdgeInsets.zero,
            title: const Text('日期'),
            subtitle: Text(formatOverrideDate(_draft.date)),
            trailing: const Icon(Icons.calendar_today_outlined, size: 18),
            onTap: _pickDate,
          ),
          const SizedBox(height: 8),
          const Text('这一天'),
          const SizedBox(height: 8),
          SegmentedButton<OverrideMode>(
            segments: const <ButtonSegment<OverrideMode>>[
              ButtonSegment<OverrideMode>(
                value: OverrideMode.cancelled,
                label: Text(
                  '停课',
                  key: ValueKey<String>('override-mode-cancelled'),
                ),
              ),
              ButtonSegment<OverrideMode>(
                value: OverrideMode.weekday,
                label: Text(
                  '按某个星期上课',
                  key: ValueKey<String>('override-mode-weekday'),
                ),
              ),
              ButtonSegment<OverrideMode>(
                value: OverrideMode.week,
                label: Text(
                  '指定周次',
                  key: ValueKey<String>('override-mode-week'),
                ),
              ),
            ],
            selected: <OverrideMode>{_draft.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                setState(() => _draft = _draft.copyWith(mode: s.first)),
          ),
          const SizedBox(height: 16),
          if (_draft.mode == OverrideMode.weekday) ...<Widget>[
            _weekdayDropdown(required: true),
            const SizedBox(height: 12),
            _weekDropdown(required: false),
          ],
          if (_draft.mode == OverrideMode.week) ...<Widget>[
            _weekDropdown(required: true),
            const SizedBox(height: 12),
            _weekdayDropdown(required: false),
          ],
          if (_draft.mode == OverrideMode.cancelled)
            Text(
              '这一天的课全部不显示（今日页、周课表、桌面小组件一致）。',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey<String>('override-note'),
            controller: _note,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              hintText: '例如：国庆调休、运动会停课',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (preview != null)
            Text(
              '${formatOverrideDate(_draft.date)}：$preview',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey<String>('override-save'),
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _weekdayDropdown({required bool required}) {
    return _dropdown(
      key: const ValueKey<String>('override-weekday'),
      label: required ? '按星期几的课上 *' : '同时指定星期（可选）',
      value: _draft.weekday,
      items: <int?>[if (!required) null, for (var d = 1; d <= 7; d++) d],
      labelOf: (d) => d == null ? '当天本来的星期（不变）' : weekdayNamesCn[d],
      onChanged: (d) => setState(
        () => _draft = d == null
            ? _draft.copyWith(clearWeekday: true)
            : _draft.copyWith(weekday: d),
      ),
    );
  }

  Widget _weekDropdown({required bool required}) {
    return _dropdown(
      key: const ValueKey<String>('override-week'),
      label: required ? '按第几周的课上 *' : '同时指定周次（可选）',
      value: _draft.week,
      items: <int?>[if (!required) null, for (var w = 1; w <= _weeks; w++) w],
      labelOf: (w) => w == null ? '这一天所在的周（不变）' : '第 $w 周',
      onChanged: (w) => setState(
        () => _draft = w == null
            ? _draft.copyWith(clearWeek: true)
            : _draft.copyWith(week: w),
      ),
    );
  }

  /// 可空 int 的下拉框：[value] 不在 [items] 里时显示「请选择」。
  Widget _dropdown({
    required Key key,
    required String label,
    required int? value,
    required List<int?> items,
    required String Function(int?) labelOf,
    required void Function(int?) onChanged,
  }) {
    final hasValue = items.contains(value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          key: key,
          value: hasValue ? value : null,
          isExpanded: true,
          isDense: true,
          hint: const Text('请选择'),
          items: <DropdownMenuItem<int?>>[
            for (final item in items)
              DropdownMenuItem<int?>(value: item, child: Text(labelOf(item))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      helpText: '选择要调整的日期',
    );
    if (picked == null) return;
    setState(
      () => _draft = _draft.copyWith(
        date: DateTime(picked.year, picked.month, picked.day),
      ),
    );
  }

  void _save() {
    final draft = _draft.copyWith(note: _note.text);
    final error = draft.validate();
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop(draft);
  }
}
