import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/course.dart';
import '../../models/timetable.dart';
import '../import/adapters/school_registry.dart';
import 'course_editor_page.dart';

/// 底部课程详情 sheet。同一格有多门课（冲突）时一次列出全部。
Future<void> showCourseDetailSheet(
  BuildContext context, {
  required List<Course> courses,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _CourseDetailSheet(courses: courses),
  );
}

class _CourseDetailSheet extends StatelessWidget {
  final List<Course> courses;

  const _CourseDetailSheet({required this.courses});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    // 课表可能已被删改，这里按 id 取最新数据。
    final live = <Course>[];
    final all = appState.currentTimetable?.courses ?? const <Course>[];
    for (final c in courses) {
      final match = all.where((x) => x.id == c.id);
      live.add(match.isEmpty ? c : match.first);
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
              if (live.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '这个时段有 ${live.length} 门课重叠',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colors.danger,
                    ),
                  ),
                ),
              for (var i = 0; i < live.length; i++) ...<Widget>[
                if (i > 0) Divider(height: 28, color: theme.colors.gridLine),
                _CourseBlockDetail(
                  course: live[i],
                  theme: theme,
                  timeText: _timeText(appState, live[i]),
                  onEdit: () async {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    await navigator.push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => CourseEditorPage(course: live[i]),
                      ),
                    );
                  },
                  onDelete: () => _confirmDelete(context, appState, live[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _timeText(AppState appState, Course course) {
    final span = ScheduleUtils.periodRange(
      appState.currentConfig,
      course.startPeriod,
      course.endPeriod,
    );
    final periods = course.startPeriod == course.endPeriod
        ? '第 ${course.startPeriod} 节'
        : '第 ${course.startPeriod}-${course.endPeriod} 节';
    return '${weekdayNamesCn[course.day.clamp(1, 7)]} · $periods · '
        '${span.start}-${span.end}';
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppState appState,
    Course course,
  ) async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定删除「${course.name}」吗？该操作不可撤销。'),
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
    if (ok != true) return;
    await appState.deleteCourse(course.id);
    if (navigator.mounted) navigator.pop();
  }
}

class _CourseBlockDetail extends StatelessWidget {
  final Course course;
  final AppTheme theme;
  final String timeText;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CourseBlockDetail({
    required this.course,
    required this.theme,
    required this.timeText,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 10,
              height: 24,
              decoration: BoxDecoration(
                color: theme.courseColor(course.colorIndex),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                course.name,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                  fontFamily: theme.titleFontFamily,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _row(Icons.schedule, timeText),
        _row(Icons.date_range, ScheduleUtils.formatWeeksText(course.weeks)),
        if (course.location != null)
          _row(Icons.place_outlined, course.location!),
        if (course.teacher != null) _row(Icons.person_outline, course.teacher!),
        if (course.note != null)
          _row(Icons.sticky_note_2_outlined, course.note!),
        _row(Icons.source_outlined, _sourceText(course.source)),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.danger,
                  side: BorderSide(color: colors.danger),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: theme.colors.onSurfaceMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: theme.colors.onSurfaceMuted),
          ),
        ),
      ],
    ),
  );

  static String _sourceText(String source) => courseSourceLabel(
    source,
    schoolNameOf: (id) => SchoolRegistry.byId(id)?.name,
  );
}

/// 课程来源的展示文案（纯函数，有单测）。
///
/// - `manual` → 手动添加；`backup` → 来自备份恢复；
/// - 导入来源标记 `'<systemType>-<schoolId>'`（`Timetable.sourceTagOf`），
///   包括 1.2.0 及以前的旧值 `zfsoft-shu` → 来自教务系统导入（能查到校名时带上校名）；
/// - 其他不认识的值按手动添加处理。
String courseSourceLabel(
  String source, {
  String? Function(String schoolId)? schoolNameOf,
}) {
  switch (source) {
    case 'manual':
      return '手动添加';
    case 'backup':
      return '来自备份恢复';
  }
  String? schoolId;
  final legacy = Timetable.legacySourceTags[source];
  if (legacy != null) {
    schoolId = legacy.$2;
  } else {
    final m = RegExp(r'^([a-z][a-z0-9]*)-(.+)$').firstMatch(source);
    if (m != null) schoolId = m.group(2);
  }
  if (schoolId == null) return '手动添加';
  final name = schoolNameOf?.call(schoolId);
  return name == null || name.isEmpty ? '来自教务系统导入' : '来自教务系统导入（$name）';
}
