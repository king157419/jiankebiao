import 'holiday_presets.dart';
import 'presets.dart';
import 'schedule_utils.dart';

/// 开学日期（第 1 周周一）是从哪来的（PLAN-1.5 D8）。
enum TermStartSource {
  /// 教务页面上识别到了「第 N 周」，按它倒推。
  detected,

  /// 学校校历里有「今天」所在的学期，直接用它的开学日期。
  schoolCalendar,

  /// 都没有：要问用户「现在是第几周？」。
  unknown,
}

/// 学校校历里的一个学期：`holidays.json` 的 `schools[id].terms` 和
/// `schools.json` 的 `termPresets` 合并后的结果。
class CalendarTerm {
  final String name;

  /// 第 1 周周一（已对齐到周一）。
  final DateTime startDate;
  final int totalWeeks;

  /// 来自 `holidays.json`（带放假 / 调休条目）；否则只来自 `schools.json`。
  final bool fromHolidays;

  const CalendarTerm({
    required this.name,
    required this.startDate,
    required this.totalWeeks,
    this.fromHolidays = false,
  });

  /// 最后一天（第 [totalWeeks] 周周日）。
  DateTime get lastDay => ScheduleUtils.addDays(startDate, totalWeeks * 7 - 1);

  /// [day] 在不在 `[startDate, startDate + totalWeeks * 7)` 里。
  bool covers(DateTime day) {
    final d = ScheduleUtils.daysBetween(startDate, day);
    return d >= 0 && d < totalWeeks * 7;
  }

  @override
  String toString() =>
      'CalendarTerm($name, ${ScheduleUtils.dateKey(startDate)}, $totalWeeks 周)';
}

/// 一所学校的全部校历学期，按开学日期排序。
///
/// `holidays.json` 优先，`schools.json` 的 [schoolPresets] 补充；两边开学日期
/// （对齐到周一后）相同的视为同一个学期，只保留 `holidays.json` 那条。
/// [schoolId] 为 null 时返回空列表。
List<CalendarTerm> schoolCalendarTerms({
  required String? schoolId,
  required HolidayPresets presets,
  List<TermPreset>? schoolPresets,
}) {
  if (schoolId == null) return const <CalendarTerm>[];
  final out = <CalendarTerm>[];
  final seen = <String>{};
  for (final t in presets.schools[schoolId]?.terms ?? const <SchoolTerm>[]) {
    final start = ScheduleUtils.mondayOf(t.startDate);
    if (!seen.add(ScheduleUtils.dateKey(start))) continue;
    out.add(
      CalendarTerm(
        name: t.name,
        startDate: start,
        totalWeeks: t.totalWeeks,
        fromHolidays: true,
      ),
    );
  }
  for (final p in schoolPresets ?? const <TermPreset>[]) {
    if (p.totalWeeks < 1) continue;
    final start = ScheduleUtils.mondayOf(p.startDate);
    if (!seen.add(ScheduleUtils.dateKey(start))) continue;
    out.add(
      CalendarTerm(name: p.name, startDate: start, totalWeeks: p.totalWeeks),
    );
  }
  out.sort((a, b) => a.startDate.compareTo(b.startDate));
  return out;
}

/// 学校校历里覆盖 [today] 的学期：先看 `holidays.json`
/// （[HolidayPresets.termCovering]），没有再看 `schools.json` 的 [schoolPresets]。
/// [schoolId] 为 null 或都不覆盖时返回 null。
CalendarTerm? schoolTermCovering({
  required String? schoolId,
  required HolidayPresets presets,
  List<TermPreset>? schoolPresets,
  required DateTime today,
}) {
  if (schoolId == null) return null;
  final fromHolidays = presets.termCovering(schoolId, today);
  if (fromHolidays != null) {
    return CalendarTerm(
      name: fromHolidays.name,
      startDate: ScheduleUtils.mondayOf(fromHolidays.startDate),
      totalWeeks: fromHolidays.totalWeeks,
      fromHolidays: true,
    );
  }
  for (final p in schoolPresets ?? const <TermPreset>[]) {
    if (p.totalWeeks < 1) continue;
    final term = CalendarTerm(
      name: p.name,
      startDate: ScheduleUtils.mondayOf(p.startDate),
      totalWeeks: p.totalWeeks,
    );
    if (term.covers(today)) return term;
  }
  return null;
}

/// 「9月14日」。
String monthDayText(DateTime d) => '${d.month}月${d.day}日';

/// 开学日期为 [start] 时 [today] 是第几周（不裁剪：开学前 <= 0）。
int weekNumberOn(DateTime start, DateTime today) {
  final d = ScheduleUtils.daysBetween(ScheduleUtils.mondayOf(start), today);
  return d >= 0 ? d ~/ 7 + 1 : -(((-d) + 6) ~/ 7) + 1;
}

/// [resolveTermStart] 的结果。
class TermResolution {
  /// 第 1 周周一；[TermStartSource.unknown] 时为 null。
  final DateTime? startDate;

  /// 校历给的总周数；只有 [TermStartSource.schoolCalendar] 有。
  final int? totalWeeks;
  final TermStartSource source;

  /// 校历学期名（[TermStartSource.schoolCalendar]）。
  final String? termName;

  /// 学校名（「按××大学校历」）；不知道时为 null。
  final String? schoolName;

  /// 「今天」是第几周（[startDate] 为 null 时也为 null）。
  final int? currentWeek;

  /// 是否属于「还没开学，取了 28 天内即将开学的校历学期」（PLAN-1.5 R2-2 / R1-3）。
  final bool upcoming;

  const TermResolution({
    required this.source,
    this.startDate,
    this.totalWeeks,
    this.termName,
    this.schoolName,
    this.currentWeek,
    this.upcoming = false,
  });

  /// 预览页「开学日期」一行的说明：
  /// - detected：「教务系统显示当前第 3 周」
  /// - schoolCalendar（学期内）：「按××大学校历 · 9月14日开学 · 现在第 4 周」
  /// - schoolCalendar（开学前）：「按××大学校历 · 9月14日开学 · 还没开学」
  /// - unknown：「还没确定 · 点这里选」
  String get label {
    switch (source) {
      case TermStartSource.detected:
        return '教务系统显示当前第 $currentWeek 周';
      case TermStartSource.schoolCalendar:
        final status = upcoming ? '还没开学' : '现在第 $currentWeek 周';
        return '按${schoolName ?? '学校'}校历 · ${monthDayText(startDate!)}开学 · '
            '$status';
      case TermStartSource.unknown:
        return '还没确定 · 点这里选';
    }
  }
}

/// 开学前多少天内导入也默认使用即将开学的校历学期。
const int kUpcomingSchoolTermWindowDays = 28;

/// 导入时推开学日期（PLAN-1.5 D8），纯函数：
///
/// 1. 教务识别到了周次（[detectedStart] 非 null）→ 用它（[detectedWeek] 只用于文案）；
/// 2. 否则学校校历（[presets] 里 `schools[schoolId].terms` ∪ [schoolPresets]，
///    `holidays.json` 优先）里有覆盖 [today] 的学期 → 用它的开学日期和总周数；
/// 3. 否则取 [kUpcomingSchoolTermWindowDays]（28 天）内即将开学的第一个校历学期
///    （按 `startDate` 升序满足 `0 < daysBetween(today, start) <= 28`），`upcoming = true`；
/// 4. 都没有 → [TermStartSource.unknown]，由界面问「现在是第几周？」。
///
/// 不再默认「今天所在的周是第一周」，也不猜最近的周一。
TermResolution resolveTermStart({
  DateTime? detectedStart,
  int? detectedWeek,
  String? schoolId,
  required HolidayPresets presets,
  List<TermPreset>? schoolPresets,
  String? schoolName,
  required DateTime today,
}) {
  if (detectedStart != null) {
    final start = ScheduleUtils.mondayOf(detectedStart);
    return TermResolution(
      source: TermStartSource.detected,
      startDate: start,
      currentWeek: detectedWeek ?? weekNumberOn(start, today),
      schoolName: schoolName,
    );
  }
  final term = schoolTermCovering(
    schoolId: schoolId,
    presets: presets,
    schoolPresets: schoolPresets,
    today: today,
  );
  if (term != null) {
    return TermResolution(
      source: TermStartSource.schoolCalendar,
      startDate: term.startDate,
      totalWeeks: term.totalWeeks,
      termName: term.name,
      schoolName: presets.schools[schoolId]?.name ?? schoolName,
      currentWeek: weekNumberOn(term.startDate, today),
    );
  }
  for (final candidate in schoolCalendarTerms(
    schoolId: schoolId,
    presets: presets,
    schoolPresets: schoolPresets,
  )) {
    final untilStart = ScheduleUtils.daysBetween(today, candidate.startDate);
    if (untilStart > 0 && untilStart <= kUpcomingSchoolTermWindowDays) {
      return TermResolution(
        source: TermStartSource.schoolCalendar,
        startDate: candidate.startDate,
        totalWeeks: candidate.totalWeeks,
        termName: candidate.name,
        schoolName: presets.schools[schoolId]?.name ?? schoolName,
        currentWeek: weekNumberOn(candidate.startDate, today),
        upcoming: true,
      );
    }
  }
  return TermResolution(
    source: TermStartSource.unknown,
    schoolName: schoolName,
  );
}
