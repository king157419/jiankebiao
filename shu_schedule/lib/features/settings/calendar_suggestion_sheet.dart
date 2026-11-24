import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/holiday_presets.dart';
import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../core/term_resolver.dart';
import '../../models/schedule_config.dart';
import '../../models/timetable.dart';
import 'date_override_editor.dart';

/// 校历建议（PLAN-1.5 D9）：按学校校历，这张课表还差什么。
///
/// - [termFix]：校历里「今天」所在学期的开学日期和课表现在的不一样，且用户 / 教务还没确认过
///   现在的开学日期 → 建议改过来；
/// - [pending]：校历里本学期还没套用的放假 / 调休（按**修正后**的开学日期算）。
class CalendarSuggestion {
  final String timetableId;

  /// 「按××大学校历」里的学校名。
  final String schoolName;

  /// 建议改成的学期（开学日期）；不用改时为 null。
  final CalendarTerm? termFix;

  /// 课表现在设的开学日期（第 1 周周一）。
  final DateTime currentStartDate;

  /// 课表现在界面上显示的是第几周（按未修正的 `config` 裁剪到 `1..totalWeeks`）。
  final int displayedCurrentWeek;

  /// 按修正后的开学日期，「今天」是第几周（不裁剪）。
  final int currentWeek;

  /// 生成建议时的「今天」（归一化到 00:00），用来把已过去的条目折叠起来。
  final DateTime today;

  /// 还没套用的放假 / 调休，按日期排序；都是学校通知里的、能直接套用的条目。
  final List<HolidaySuggestion> pending;

  /// 本校本学期的内容指纹（[calendarSuggestionTermKey]）；「先不用」和「一键套用」都写它。
  final String termKey;

  const CalendarSuggestion({
    required this.timetableId,
    required this.schoolName,
    required this.termFix,
    required this.currentStartDate,
    required this.displayedCurrentWeek,
    required this.currentWeek,
    required this.today,
    required this.pending,
    required this.termKey,
  });

  /// 兼容旧名：同 [termKey]。
  String get dismissKey => termKey;

  /// 「一键套用」要写入的调休 / 停课（包含过去和未来的全部未套用条目）。
  Map<DateTime, DateOverride> get overrides => <DateTime, DateOverride>{
    for (final s in pending) s.date: s.override!,
  };

  /// [dismissed]（`AppSettings.calendarSuggestionDismissed`）里记着同一个学期内容指纹：
  /// 对这所学校这个学期的同一份条目已经点过「先不用」或「一键套用」。
  bool isDismissedIn(Map<String, String> dismissed) =>
      dismissed[timetableId] == termKey;
}

/// 学期内容指纹 `'<schoolId>|<term.startDate>|<排好序的 entries(date→override) 的 hash>'`
/// （不含课表自己的开学日期，不含假期表顶层 `updatedAt`）。
///
/// 课表没有 `schoolId` 或匹配不到任何校历学期时返回 null。
String? calendarSuggestionTermKey({
  required Timetable tt,
  required HolidayPresets presets,
  required DateTime today,
  List<TermPreset>? schoolPresets,
}) {
  final schoolId = tt.schoolId;
  if (schoolId == null) return null;
  final config = tt.config;
  final covering = schoolTermCovering(
    schoolId: schoolId,
    presets: presets,
    schoolPresets: schoolPresets,
    today: today,
  );
  DateTime? termStart;
  int? totalWeeks;
  if (covering != null && _overlaps(config, covering)) {
    termStart = covering.startDate;
    totalWeeks = covering.totalWeeks;
  } else {
    final cfgWeeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
    final cfgEnd = ScheduleUtils.addDays(config.startDate, cfgWeeks * 7 - 1);
    final schoolTerm = presets.schools[schoolId]?.termFor(
      config.startDate,
      cfgEnd,
    );
    if (schoolTerm != null) {
      termStart = schoolTerm.startDate;
      totalWeeks = schoolTerm.totalWeeks;
    } else {
      final terms = schoolCalendarTerms(
        schoolId: schoolId,
        presets: presets,
        schoolPresets: schoolPresets,
      );
      for (final t in terms) {
        if (ScheduleUtils.daysBetween(t.startDate, config.startDate) == 0) {
          termStart = t.startDate;
          totalWeeks = t.totalWeeks;
          break;
        }
      }
      if (termStart == null) {
        for (final t in terms) {
          if (_overlaps(config, t)) {
            termStart = t.startDate;
            totalWeeks = t.totalWeeks;
            break;
          }
        }
      }
    }
  }
  if (termStart == null || totalWeeks == null) return null;
  final canonical = ScheduleConfig(
    name: '',
    startDate: termStart,
    totalWeeks: totalWeeks,
  );
  final entries = <String>[];
  for (final s
      in presets.planFor(config: canonical, schoolId: schoolId).items) {
    if (!s.fromSchool || s.override == null) continue;
    final ov = s.override!;
    final spec = ov.cancelled
        ? 'off'
        : 'act:${ov.actAsWeek ?? ''}:${ov.actAsWeekday ?? ''}';
    entries.add('${ScheduleUtils.dateKey(s.date)}=>$spec:${ov.note ?? ''}');
  }
  entries.sort();
  final digest = crypto.sha256
      .convert(utf8.encode(entries.join('\n')))
      .toString()
      .substring(0, 16);
  return '$schoolId|${ScheduleUtils.dateKey(termStart)}|$digest';
}

/// 纯函数：[tt] 按学校校历还差什么；什么都不差（或课表没有 `schoolId`）返回 null。
///
/// - 开学日期：[schoolPresets]（`schools.json` 的 `termPresets`）和 [presets]
///   （`holidays.json`）里有覆盖 [today] 的学期，课表的开学日期和它不同、课表的学期
///   范围和它有重叠（说明这张课表就是这学期的，只是开学日期错了），课表的开学日期
///   **不是该校任何一个已知学期的开学日期**，且 [termStartConfirmed] 里没有确认过课表当前的
///   开学日期时，建议改成「今天」所在学期的。提前导入的下学期课表、还在用的上学期课表、
///   用户或教务确认过的开学日期都不去动。[allowTermFix] 为 false 时也不给这一条（刚导入完）。
/// - 放假 / 调休：`planFor(修正后的配置)` 里来自学校通知、还没套用（目标日期上
///   没有相同设置）的条目。国家安排的条目不算（那是「套用节假日安排」页的事）。
CalendarSuggestion? buildCalendarSuggestion({
  required Timetable tt,
  required HolidayPresets presets,
  required DateTime today,
  List<TermPreset>? schoolPresets,
  String? schoolName,
  bool allowTermFix = true,
  Map<String, String> termStartConfirmed = const <String, String>{},
}) {
  final schoolId = tt.schoolId;
  if (schoolId == null) return null;
  final config = tt.config;
  final confirmed =
      termStartConfirmed[tt.id] == ScheduleConfig.dateKey(config.startDate);
  CalendarTerm? fix;
  if (allowTermFix && !confirmed) {
    final term = schoolTermCovering(
      schoolId: schoolId,
      presets: presets,
      schoolPresets: schoolPresets,
      today: today,
    );
    final known = schoolCalendarTerms(
      schoolId: schoolId,
      presets: presets,
      schoolPresets: schoolPresets,
    ).any((t) => ScheduleUtils.daysBetween(t.startDate, config.startDate) == 0);
    if (term != null && !known && _overlaps(config, term)) fix = term;
  }
  final fixed = fix == null
      ? config
      : config.copyWith(startDate: fix.startDate);
  final pending = presets
      .planFor(config: fixed, schoolId: schoolId)
      .items
      .where((s) => s.fromSchool && s.applicable)
      .toList();
  if (fix == null && pending.isEmpty) return null;
  final termKey =
      calendarSuggestionTermKey(
        tt: tt,
        presets: presets,
        today: today,
        schoolPresets: schoolPresets,
      ) ??
      '$schoolId|${ScheduleUtils.dateKey(fixed.startDate)}|';
  return CalendarSuggestion(
    timetableId: tt.id,
    schoolName: presets.schools[schoolId]?.name ?? schoolName ?? '学校',
    termFix: fix,
    currentStartDate: config.startDate,
    displayedCurrentWeek: ScheduleUtils.weekOf(today, config),
    currentWeek: weekNumberOn(fixed.startDate, today),
    today: DateTime(today.year, today.month, today.day),
    pending: pending,
    termKey: termKey,
  );
}

/// 课表的学期 `[startDate, startDate + totalWeeks * 7)` 和 [term] 有没有重叠。
bool _overlaps(ScheduleConfig config, CalendarTerm term) {
  final weeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
  final end = ScheduleUtils.addDays(config.startDate, weeks * 7 - 1);
  return ScheduleUtils.daysBetween(config.startDate, term.lastDay) >= 0 &&
      ScheduleUtils.daysBetween(term.startDate, end) >= 0;
}

/// 面板上的两个按钮。
enum CalendarSuggestionAction { apply, later }

/// 弹校历建议面板，按用户的选择处理：
/// - 「一键套用」→ [AppState.applyCalendarSuggestion]（同时记下 termKey 与已确认开学日期，
///   只保存一次），SnackBar「已按校历设置」+「撤销」；
/// - 「先不用」→ [AppState.dismissCalendarSuggestion] 记下 termKey；
/// - 直接关掉面板 → 什么都不做（下次启动还会提示）。
///
/// 返回是否套用了。
Future<bool> offerCalendarSuggestion(
  BuildContext context,
  CalendarSuggestion suggestion,
) async {
  final appState = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final action = await showModalBottomSheet<CalendarSuggestionAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CalendarSuggestionSheet(
      key: const ValueKey<String>('calendar-suggestion-sheet'),
      suggestion: suggestion,
    ),
  );
  switch (action) {
    case null:
      return false;
    case CalendarSuggestionAction.later:
      await appState.dismissCalendarSuggestion(
        suggestion.timetableId,
        suggestion.termKey,
      );
      return false;
    case CalendarSuggestionAction.apply:
      final id = suggestion.timetableId;
      final previousConfirmed = appState.settings.termStartConfirmed[id];
      final previousDismissed =
          appState.settings.calendarSuggestionDismissed[id];
      final previous = await appState.applyCalendarSuggestion(
        id,
        startDate: suggestion.termFix?.startDate,
        overrides: suggestion.overrides,
        termKey: suggestion.termKey,
      );
      if (previous == null) return false;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const ValueKey<String>('calendar-suggestion-applied'),
            content: const Text('已按校历设置'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => appState.restoreTimetableConfig(
                id,
                previous,
                previousConfirmedStart: previousConfirmed,
                restoreDismissed: true,
                previousDismissedKey: previousDismissed,
              ),
            ),
          ),
        );
      return true;
  }
}

/// 面板内容：标题「按××大学校历」，开学日期一段（有 [CalendarSuggestion.termFix] 时）、
/// 放假 / 调休一段（有 [CalendarSuggestion.pending] 时），底下「先不用」「一键套用」。
/// 只用 `Theme.of`，不依赖 `ThemeController`。
class CalendarSuggestionSheet extends StatelessWidget {
  final CalendarSuggestion suggestion;

  const CalendarSuggestionSheet({super.key, required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final danger = theme.textTheme.bodySmall?.copyWith(color: scheme.error);
    final fix = suggestion.termFix;
    final pending = suggestion.pending;
    final todayFloor = DateTime(
      suggestion.today.year,
      suggestion.today.month,
      suggestion.today.day,
    );
    final upcoming = pending
        .where((s) => !s.date.isBefore(todayFloor))
        .toList();
    final pastCount = pending.length - upcoming.length;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Padding(
        // 底部留出手势条 / 导航栏的位置（useSafeArea 只管顶部）。
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '按${suggestion.schoolName}校历',
              key: const ValueKey<String>('calendar-suggestion-title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('套用后还可以在「学期设置」里改', style: muted),
            if (fix != null) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                '开学日期：${monthDayText(fix.startDate)}'
                '（现在第 ${suggestion.currentWeek} 周）',
                key: const ValueKey<String>('calendar-suggestion-term'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 2),
              Text(
                '现在课表显示的是第 ${suggestion.displayedCurrentWeek} 周',
                style: muted,
              ),
            ],
            if (pending.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                '放假 / 调休 ${pending.length} 条',
                key: const ValueKey<String>('calendar-suggestion-pending'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final s in upcoming) _row(s, theme, muted, danger),
                    if (pastCount > 0)
                      Padding(
                        key: const ValueKey<String>(
                          'calendar-suggestion-past-summary',
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '另有 $pastCount 条已经过去的，也会一起补上',
                          style: muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton(
                  key: const ValueKey<String>('calendar-suggestion-later'),
                  onPressed: () =>
                      Navigator.of(context).pop(CalendarSuggestionAction.later),
                  child: const Text('先不用'),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey<String>('calendar-suggestion-apply'),
                  onPressed: () =>
                      Navigator.of(context).pop(CalendarSuggestionAction.apply),
                  child: const Text('一键套用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 一条今天及以后的放假 / 调休：日期统一「9月20日 周日」，只显示一种描述（有 note 用 note，
  /// 否则用 describe）；会覆盖手动设置时标红「将覆盖：…」。
  Widget _row(
    HolidaySuggestion s,
    ThemeData theme,
    TextStyle? muted,
    TextStyle? danger,
  ) {
    final existing = s.existing;
    final note = s.note?.trim();
    final detail = note != null && note.isNotEmpty
        ? note
        : describeDateOverride(s.override!);
    final existingNote = existing?.note?.trim();
    final existingDetail = existing == null
        ? ''
        : (existingNote != null && existingNote.isNotEmpty
              ? existingNote
              : describeDateOverride(existing));
    return Padding(
      key: ValueKey<String>(
        'calendar-suggestion-item-${ScheduleUtils.dateKey(s.date)}',
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${monthDayText(s.date)} ${weekdayNamesCn[s.date.weekday]}',
            style: theme.textTheme.bodyMedium,
          ),
          Text(detail, style: muted),
          if (s.conflicts && existing != null)
            Text('将覆盖：$existingDetail', style: danger),
          if (s.warning != null) Text(s.warning!, style: danger),
        ],
      ),
    );
  }
}
