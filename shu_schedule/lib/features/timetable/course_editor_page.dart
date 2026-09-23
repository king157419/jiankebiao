import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/course.dart';
import 'course_form.dart';

/// 新建 / 编辑课程。
///
/// [course] 为 null 表示新建；[initialDay] / [initialStartPeriod] 用于
/// 「长按空格子新建」时预填星期与节次。
///
/// 录入提效（v1.3.0）：
/// - 「保存并继续添加」（只在新建时出现）：保存后留在本页，保留星期 / 节次 / 周次，
///   清空课程名、教师、地点、备注，下一门课是一门独立的新课（不共享 groupId）；
/// - 「复制到其他星期」：多选星期，保存时每个星期各生成一门同样的课，
///   和本课共用一个 `groupId`（改颜色会同步）；
/// - 教师 / 地点输入时从当前课表已有的值里给补全候选。
class CourseEditorPage extends StatefulWidget {
  final Course? course;
  final int? initialDay;
  final int? initialStartPeriod;

  const CourseEditorPage({
    super.key,
    this.course,
    this.initialDay,
    this.initialStartPeriod,
  });

  @override
  State<CourseEditorPage> createState() => _CourseEditorPageState();
}

class _CourseEditorPageState extends State<CourseEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late final TextEditingController _note;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _teacherFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();

  /// 「复制到其他星期」选中的星期（不含 [_day] 本身）。
  final Set<int> _copyDays = <int>{};

  /// 本页用「保存并继续添加」已经加了几门（给 SnackBar 用）。
  int _addedCount = 0;

  late int _day;
  late int _startPeriod;
  late int _endPeriod;
  late List<int> _weeks;
  late int _colorIndex;
  bool _colorTouched = false;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _note = TextEditingController(text: c?.note ?? '');
    _day = c?.day ?? widget.initialDay ?? 1;
    _startPeriod = c?.startPeriod ?? widget.initialStartPeriod ?? 1;
    _endPeriod = c?.endPeriod ?? widget.initialStartPeriod ?? 1;
    _weeks = List<int>.from(c?.weeks ?? const <int>[]);
    _colorIndex = c?.colorIndex ?? 0;
    _colorTouched = c != null;
    if (_weeks.isEmpty) {
      // 新建时默认整学期。
      _weeks = CourseForm.allWeeks(18);
    }
    _name.addListener(_syncColorWithName);
  }

  @override
  void dispose() {
    _name.removeListener(_syncColorWithName);
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    _note.dispose();
    _nameFocus.dispose();
    _teacherFocus.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  void _syncColorWithName() {
    if (_colorTouched) return;
    final next = CourseForm.defaultColorIndex(_name.text.trim());
    if (next != _colorIndex) setState(() => _colorIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final config = appState.currentConfig;
    final periodCount = config.periodCount;
    final totalWeeks = config.totalWeeks;
    final isNew = widget.course == null;
    final existingCourses =
        appState.currentTimetable?.courses ?? const <Course>[];
    final teacherHistory = CourseForm.historyValues(
      existingCourses,
      (c) => c.teacher,
    );
    final locationHistory = CourseForm.historyValues(
      existingCourses,
      (c) => c.location,
    );

    // 新建时如果还没碰过周次，跟随当前课表总周数。
    if (isNew && _weeks.length == 18 && totalWeeks != 18) {
      _weeks = CourseForm.allWeeks(totalWeeks);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '新建课程' : '编辑课程'),
        actions: <Widget>[
          TextButton(
            onPressed: () => _save(appState, periodCount),
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('course-name'),
            controller: _name,
            focusNode: _nameFocus,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '课程名 *',
              hintText: '例如：高等数学 A(一)',
            ),
          ),
          const SizedBox(height: 12),
          _historyField(
            key: const ValueKey<String>('course-teacher'),
            controller: _teacher,
            focusNode: _teacherFocus,
            label: '教师',
            history: teacherHistory,
          ),
          const SizedBox(height: 12),
          _historyField(
            key: const ValueKey<String>('course-location'),
            controller: _location,
            focusNode: _locationFocus,
            label: '地点',
            history: locationHistory,
          ),
          const SizedBox(height: 20),
          _label(theme, '时间'),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _dropdown<int>(
                  label: '星期',
                  value: _day,
                  items: <int>[for (var d = 1; d <= 7; d++) d],
                  labelOf: (d) => weekdayNamesCn[d],
                  onChanged: (d) => setState(() {
                    _day = d;
                    _copyDays.remove(d);
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdown<int>(
                  label: '起始节次',
                  value: _startPeriod.clamp(1, periodCount),
                  items: <int>[for (var p = 1; p <= periodCount; p++) p],
                  labelOf: (p) => '第 $p 节',
                  onChanged: (p) => setState(() {
                    _startPeriod = p;
                    if (_endPeriod < p) _endPeriod = p;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdown<int>(
                  label: '结束节次',
                  value: _endPeriod.clamp(1, periodCount),
                  items: <int>[for (var p = 1; p <= periodCount; p++) p],
                  labelOf: (p) => '第 $p 节',
                  onChanged: (p) => setState(() => _endPeriod = p),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _timeHint(appState, periodCount),
            style: TextStyle(fontSize: 12, color: theme.colors.onSurfaceMuted),
          ),
          const SizedBox(height: 16),
          _copyToDays(theme),
          const SizedBox(height: 20),
          _label(theme, '周次（已选 ${_weeks.length} 周）'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              _quickChip('全部', () => CourseForm.allWeeks(totalWeeks)),
              _quickChip('单周', () => CourseForm.oddWeeks(totalWeeks)),
              _quickChip('双周', () => CourseForm.evenWeeks(totalWeeks)),
              _quickChip('前半', () => CourseForm.firstHalfWeeks(totalWeeks)),
              _quickChip('后半', () => CourseForm.secondHalfWeeks(totalWeeks)),
              _quickChip('清空', () => const <int>[]),
            ],
          ),
          const SizedBox(height: 10),
          _weekGrid(theme, totalWeeks),
          const SizedBox(height: 6),
          Text(
            _weeks.isEmpty ? '尚未选择周次' : ScheduleUtils.formatWeeksText(_weeks),
            style: TextStyle(fontSize: 12, color: theme.colors.onSurfaceMuted),
          ),
          const SizedBox(height: 20),
          _label(theme, '颜色'),
          const SizedBox(height: 8),
          _colorPicker(theme),
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey<String>('course-save'),
            onPressed: () => _save(appState, periodCount),
            child: Text(isNew ? '添加课程' : '保存修改'),
          ),
          if (isNew) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey<String>('course-save-continue'),
              onPressed: () =>
                  _save(appState, periodCount, continueAdding: true),
              child: const Text('保存并继续添加'),
            ),
            const SizedBox(height: 4),
            Text(
              '保留星期、节次和周次，只清空课程名、教师和地点，适合连着录一整天的课。',
              style: TextStyle(
                fontSize: 12,
                color: theme.colors.onSurfaceMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 带历史补全的输入框（教师 / 地点）。
  Widget _historyField({
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required List<String> history,
  }) {
    return Autocomplete<String>(
      key: key,
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) =>
          CourseForm.matchSuggestions(history, value.text),
      fieldViewBuilder: (context, fieldController, fieldFocus, onSubmitted) =>
          TextField(
            controller: fieldController,
            focusNode: fieldFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => onSubmitted(),
            decoration: InputDecoration(
              labelText: label,
              helperText: history.isEmpty ? null : '输入时会提示本课表里用过的$label',
            ),
          ),
    );
  }

  /// 「复制到其他星期」：多选星期，保存时每个星期各生成一门同样的课。
  Widget _copyToDays(AppTheme theme) {
    final selected = (_copyDays.toList()..sort())
        .map((d) => weekdayNamesCn[d])
        .join('、');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _label(theme, '复制到其他星期'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            for (var d = 1; d <= 7; d++)
              if (d != _day)
                FilterChip(
                  key: ValueKey<String>('copy-day-$d'),
                  label: Text(weekdayNamesCn[d]),
                  selected: _copyDays.contains(d),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _copyDays.add(d);
                    } else {
                      _copyDays.remove(d);
                    }
                  }),
                ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _copyDays.isEmpty
              ? '一门课一周上几次时，勾上其他几天，保存时一起生成（节次、周次相同，颜色联动）。'
              : '保存时会在$selected再各生成一门同样的课，改颜色时一起变。',
          style: TextStyle(fontSize: 12, color: theme.colors.onSurfaceMuted),
        ),
      ],
    );
  }

  Widget _label(AppTheme theme, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: theme.colors.headerText,
    ),
  );

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
  }) {
    final effective = items.contains(value)
        ? value
        : (items.isEmpty ? null : items.first);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: effective,
          isExpanded: true,
          isDense: true,
          items: <DropdownMenuItem<T>>[
            for (final item in items)
              DropdownMenuItem<T>(value: item, child: Text(labelOf(item))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  String _timeHint(AppState appState, int periodCount) {
    if (periodCount < 1) return '当前作息表为空，请先在设置里添加节次';
    final span = ScheduleUtils.periodRange(
      appState.currentConfig,
      _startPeriod,
      _endPeriod,
    );
    return '${span.start} - ${span.end}';
  }

  Widget _quickChip(String label, List<int> Function() build) {
    return ActionChip(
      label: Text(label),
      onPressed: () => setState(() => _weeks = List<int>.from(build())),
    );
  }

  Widget _weekGrid(AppTheme theme, int totalWeeks) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (var w = 1; w <= totalWeeks; w++)
          _WeekChip(
            week: w,
            selected: _weeks.contains(w),
            theme: theme,
            onTap: () => setState(() {
              if (_weeks.contains(w)) {
                _weeks.remove(w);
              } else {
                _weeks.add(w);
              }
              _weeks = Course.normalizeWeeks(_weeks);
            }),
          ),
      ],
    );
  }

  Widget _colorPicker(AppTheme theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (var i = 0; i < theme.courseColors.length; i++)
          Semantics(
            label: '课程颜色 ${i + 1}',
            selected: _colorIndex == i,
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              onTap: () => setState(() {
                _colorIndex = i;
                _colorTouched = true;
              }),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.courseColor(i),
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  border: Border.all(
                    color: _colorIndex == i
                        ? theme.colors.primary
                        : theme.colors.gridLine,
                    width: _colorIndex == i ? 3 : 1,
                  ),
                ),
                child: _colorIndex == i
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: theme.courseTextOnBlock,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _save(
    AppState appState,
    int periodCount, {
    bool continueAdding = false,
  }) async {
    final error = CourseForm.validateAll(
      name: _name.text,
      day: _day,
      startPeriod: _startPeriod,
      endPeriod: _endPeriod,
      periodCount: periodCount,
      weeks: _weeks,
    );
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final existing = widget.course;
    final copyDays = _copyDays.where((d) => d != _day).toList()..sort();
    // 复制到其他星期时，本课和副本共用一个分组；编辑一门已有分组的课时沿用原分组。
    var groupId = existing?.groupId;
    if (copyDays.isNotEmpty) groupId ??= appState.newId();
    final course = CourseForm.normalize(
      Course(
        id: existing?.id ?? '',
        name: _name.text.trim(),
        teacher: _teacher.text.trim().isEmpty ? null : _teacher.text.trim(),
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        day: _day,
        startPeriod: _startPeriod,
        endPeriod: _endPeriod,
        weeks: _weeks,
        colorIndex: _colorIndex,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        source: existing?.source ?? 'manual',
        // 分组 / 外部键不在编辑器里露出，但编辑时必须原样保留：
        // 丢了 groupId 同组改色就断了，丢了 externalKey 重新导入就合并不上。
        groupId: groupId,
        externalKey: existing?.externalKey,
      ),
      periodCount: periodCount,
    );
    final copies = groupId == null
        ? const <Course>[]
        : CourseForm.copiesToDays(
            course,
            copyDays,
            groupId: groupId,
            newId: appState.newId,
          );

    if (existing == null) {
      if (copies.isEmpty) {
        await appState.addCourse(course);
      } else {
        await appState.addCourses(<Course>[course, ...copies]);
      }
    } else {
      await appState.updateCourse(course);
      if (copies.isNotEmpty) await appState.addCourses(copies);
    }
    if (!mounted) return;
    if (continueAdding) {
      _resetForNext(course.name, copies.length);
      return;
    }
    Navigator.of(context).pop(true);
  }

  /// 「保存并继续添加」之后：保留星期 / 节次 / 周次，清空其余字段。
  /// 下一门是一门独立的新课（groupId 在 [_save] 里按「复制到其他星期」重新决定）。
  void _resetForNext(String savedName, int copies) {
    _addedCount += 1 + copies;
    setState(() {
      _name.clear();
      _teacher.clear();
      _location.clear();
      _note.clear();
      _copyDays.clear();
      _colorTouched = false;
      _colorIndex = 0;
    });
    _nameFocus.requestFocus();
    final what = copies > 0
        ? '「$savedName」（共 ${copies + 1} 个时段）'
        : '「$savedName」';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已添加$what，继续填下一门（本页已加 $_addedCount 门）'),
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

class _WeekChip extends StatelessWidget {
  final int week;
  final bool selected;
  final AppTheme theme;
  final VoidCallback onTap;

  const _WeekChip({
    required this.week,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '第 $week 周',
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? theme.colors.primary : theme.colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? theme.colors.primary : theme.colors.outline,
            ),
          ),
          child: Text(
            '$week',
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? theme.colors.onPrimary
                  : theme.colors.onSurfaceMuted,
            ),
          ),
        ),
      ),
    );
  }
}
