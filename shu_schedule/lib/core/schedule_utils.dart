import '../models/course.dart';
import '../models/period_time.dart';
import '../models/schedule_config.dart';
import '../models/timetable.dart';
import 'presets.dart';

/// 一段课程的起止时刻。
typedef PeriodSpanTime = ({String start, String end});

/// 某个日历日「实际按哪一周、星期几上课」——调休 / 停课展开后的结果。
///
/// 周视图、小组件快照、上课提醒都从 [ScheduleUtils.effectiveDayOf] 拿这个，
/// 保证三处对同一天的理解一致。
class EffectiveDay {
  /// 日历日（时分秒已清零）。
  final DateTime date;

  /// 这一天在日历上属于第几周（不裁剪，开学前 <= 0）。
  final int calendarWeek;

  /// 实际按第几周上课（没有调休时 = [calendarWeek]）。
  final int week;

  /// 实际按星期几上课，1..7（没有调休时 = `date.weekday`）。
  final int weekday;

  /// 这一天停课。
  final bool cancelled;

  /// 这一天的原始调休规则；没有为 null。
  final DateOverride? override;

  const EffectiveDay({
    required this.date,
    required this.calendarWeek,
    required this.week,
    required this.weekday,
    required this.cancelled,
    this.override,
  });

  /// 这一天是否被调休 / 停课改动过（只写了备注的不算）。
  bool get isOverridden => override?.changesSchedule ?? false;

  /// 「停课」/「调休」/ null，给小组件快照用（Kotlin 侧比对「停课」字面量）。
  String? get label => override?.shortLabel;

  /// 周视图列头的单字角标（v1.4.0）：停课 →「休」，按别的星期 / 周次上课 →「补」；
  /// 没有改动课程（没有设置 / 只写了备注）→ null。和 [label] 分开，
  /// 免得改动小组件快照和 Kotlin 依赖的「停课」/「调休」。
  String? get badge {
    final o = override;
    if (o == null || !o.changesSchedule) return null;
    return cancelled ? '休' : '补';
  }

  /// 完整说明：「停课」/「调休，按第 5 周周一上课」/「调休，按周一上课」；
  /// 没有调休时为 null。
  String? get description {
    final o = override;
    if (o == null || !o.changesSchedule) return null;
    if (cancelled) return '停课';
    final weekText = o.actAsWeek != null ? '第 $week 周' : '';
    return '调休，按$weekText${weekdayNamesCn[weekday.clamp(1, 7)]}上课';
  }
}

/// 课表相关的纯函数工具集。所有函数都必须对越界/脏数据保持不崩溃。
class ScheduleUtils {
  ScheduleUtils._();

  /// 单双周过滤模式。
  static const int _parityAll = 0;
  static const int _parityOdd = 1;
  static const int _parityEven = 2;

  /// 允许的最大周次，用于防御脏数据（如 "1-9999周"）。
  static const int maxWeek = 60;

  // ---------------------------------------------------------------- 周次文本

  /// 解析正方教务的周次文本 `zcd`，返回升序去重的周数列表。
  ///
  /// 支持：`1-16周`、`1-15周(单)`、`2-16周(双)`、`1-8周,10-16周`、`3周`、
  /// `1,3,5周`、`1-4周,6-8周(双)`、`第1-16周`、全角逗号/括号、`1~16周`、
  /// `1-16周单`、空串或 null → `[]`。
  static List<int> parseWeeksText(String? raw) {
    if (raw == null) return <int>[];
    var text = raw;
    // 归一化全角与各种破折号。
    const replacements = <String, String>{
      '，': ',',
      '、': ',',
      '；': ',',
      ';': ',',
      '（': '(',
      '）': ')',
      '［': '(',
      '］': ')',
      '[': '(',
      ']': ')',
      '－': '-',
      '—': '-',
      '–': '-',
      '～': '-',
      '~': '-',
      '至': '-',
      '到': '-',
    };
    replacements.forEach((from, to) {
      text = text.replaceAll(from, to);
    });
    // 去掉空白、"第"、"周次"、"周"。
    text = text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('第', '')
        .replaceAll('周次', '')
        .replaceAll('周', '');
    if (text.isEmpty) return <int>[];

    final result = <int>{};
    for (final rawPart in text.split(',')) {
      var part = rawPart;
      if (part.isEmpty) continue;

      var parity = _parityAll;
      if (part.contains('单')) {
        parity = _parityOdd;
      } else if (part.contains('双')) {
        parity = _parityEven;
      }
      // 只保留数字和连字符。
      part = part.replaceAll(RegExp(r'[^0-9\-]'), '');
      if (part.isEmpty) continue;

      final range = RegExp(r'^(\d+)-(\d+)$').firstMatch(part);
      if (range != null) {
        var from = int.parse(range.group(1)!);
        var to = int.parse(range.group(2)!);
        if (from > to) {
          final tmp = from;
          from = to;
          to = tmp;
        }
        if (from < 1) from = 1;
        if (to > maxWeek) to = maxWeek;
        for (var w = from; w <= to; w++) {
          if (_matchesParity(w, parity)) result.add(w);
        }
        continue;
      }

      final single = RegExp(r'^(\d+)$').firstMatch(part);
      if (single != null) {
        final w = int.parse(single.group(1)!);
        if (w >= 1 && w <= maxWeek && _matchesParity(w, parity)) {
          result.add(w);
        }
        continue;
      }

      // 形如 "1-4-6" 这类异常串：取所有数字当单周处理。
      for (final m in RegExp(r'\d+').allMatches(part)) {
        final w = int.parse(m.group(0)!);
        if (w >= 1 && w <= maxWeek && _matchesParity(w, parity)) {
          result.add(w);
        }
      }
    }

    final list = result.toList()..sort();
    return list;
  }

  static bool _matchesParity(int week, int parity) {
    switch (parity) {
      case _parityOdd:
        return week.isOdd;
      case _parityEven:
        return week.isEven;
      default:
        return true;
    }
  }

  /// 把周数列表压缩成人类可读文本，例如 `[1,2,3,5]` → `1-3,5周`。
  static String formatWeeksText(List<int> weeks) {
    final sorted = Course.normalizeWeeks(weeks);
    if (sorted.isEmpty) return '';
    final segments = <String>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (var i = 1; i <= sorted.length; i++) {
      final cur = i < sorted.length ? sorted[i] : -1;
      if (cur != prev + 1) {
        segments.add(start == prev ? '$start' : '$start-$prev');
        start = cur;
      }
      prev = cur;
    }
    return '${segments.join(',')}周';
  }

  // ------------------------------------------------------------------ 周次

  /// 两个「日历日」之间相差多少天。用 UTC 归一化，避免夏令时导致
  /// `difference().inDays` 少算/多算一天。
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// 不做任何裁剪的周次：开学当周为 1，开学前为 0 或负数。
  static int rawWeekOf(DateTime date, ScheduleConfig config) {
    final diffDays = daysBetween(config.startDate, date);
    if (diffDays >= 0) return diffDays ~/ 7 + 1;
    // 向下取整，保证开学前一周是 0，再前一周是 -1。
    return -(((-diffDays) + 6) ~/ 7) + 1;
  }

  /// 裁剪到 `[1, totalWeeks]` 的周次，适合直接喂给 UI。
  static int weekOf(DateTime date, ScheduleConfig config) {
    final raw = rawWeekOf(date, config);
    final max = config.totalWeeks < 1 ? 1 : config.totalWeeks;
    if (raw < 1) return 1;
    if (raw > max) return max;
    return raw;
  }

  /// 该日期是否落在学期内。
  static bool isDuringTerm(DateTime date, ScheduleConfig config) {
    final raw = rawWeekOf(date, config);
    return raw >= 1 && raw <= config.totalWeeks;
  }

  /// 第 [week] 周、星期 [day]（1..7）对应的日期。
  static DateTime dateOf(ScheduleConfig config, int week, int day) {
    final w = week < 1 ? 1 : week;
    final d = day < 1 ? 1 : (day > 7 ? 7 : day);
    return addDays(config.startDate, (w - 1) * 7 + (d - 1));
  }

  /// 日历意义上的「加 N 天」，跨夏令时不会出现 23:00 这种错位。
  static DateTime addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  /// 第 [week] 周的周一。
  static DateTime mondayOfWeek(ScheduleConfig config, int week) =>
      dateOf(config, week, 1);

  /// [date] 所在自然周的周一（周日算本周最后一天）。
  static DateTime mondayOf(DateTime date) =>
      addDays(date, -(date.weekday - DateTime.monday));

  // ------------------------------------------------------------------ 节次

  /// 取 [start]..[end] 节的起止时刻。越界会被裁剪到已有节次；
  /// 若作息表为空则返回 `(start: '', end: '')`。
  static PeriodSpanTime periodRange(ScheduleConfig config, int start, int end) {
    final periods = config.periods;
    if (periods.isEmpty) return (start: '', end: '');
    final sorted = List<PeriodTime>.from(periods)
      ..sort((a, b) => a.index.compareTo(b.index));
    final minIndex = sorted.first.index;
    final maxIndex = sorted.last.index;

    var s = start;
    var e = end;
    if (s > e) {
      final tmp = s;
      s = e;
      e = tmp;
    }
    if (s < minIndex) s = minIndex;
    if (s > maxIndex) s = maxIndex;
    if (e > maxIndex) e = maxIndex;
    if (e < s) e = s;

    final first = _nearest(sorted, s);
    final last = _nearest(sorted, e);
    return (start: first.start, end: last.end);
  }

  static PeriodTime _nearest(List<PeriodTime> sorted, int index) {
    for (final p in sorted) {
      if (p.index == index) return p;
    }
    // 索引不连续时退化为「不大于 index 的最后一节」。
    PeriodTime best = sorted.first;
    for (final p in sorted) {
      if (p.index <= index) best = p;
    }
    return best;
  }

  // ---------------------------------------------------------------- 休息带

  /// 自动推导休息带的阈值：相邻两节间隔 >= 这么多分钟就画一条带。
  static const int autoBreakMinGapMinutes = 40;

  /// 在哪几节之后画休息带，返回 [PeriodTime.index] 升序列表。
  ///
  /// - [ScheduleConfig.breakAfter] 非 null：用手动指定的值（只保留作息表里
  ///   真实存在、且不是最后一节的 index）；
  /// - 否则自动推导：按 index 排好序后，`下一节开始 - 这一节结束 >=`
  ///   [autoBreakMinGapMinutes] 分钟的位置画一条。
  ///
  /// 默认 12 节示例作息（11:40→13:00、16:40→18:00）推导出 `[4, 8]`，
  /// 与 v1.2.0 写死的「第 4、8 节后」一致。
  static List<int> breakAfterIndices(ScheduleConfig config) {
    final sorted = List<PeriodTime>.from(config.periods)
      ..sort((a, b) => a.index.compareTo(b.index));
    if (sorted.length < 2) return <int>[];
    final manual = config.breakAfter;
    if (manual != null) {
      final allowed = <int>{
        for (var i = 0; i < sorted.length - 1; i++) sorted[i].index,
      };
      return manual.where(allowed.contains).toSet().toList()..sort();
    }
    return autoBreakAfterIndices(sorted);
  }

  /// 纯自动推导（不看手动设置），[periods] 不要求有序。
  static List<int> autoBreakAfterIndices(
    List<PeriodTime> periods, {
    int minGapMinutes = autoBreakMinGapMinutes,
  }) {
    final sorted = List<PeriodTime>.from(periods)
      ..sort((a, b) => a.index.compareTo(b.index));
    final result = <int>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final gap = sorted[i + 1].startMinutes - sorted[i].endMinutes;
      if (gap >= minGapMinutes) result.add(sorted[i].index);
    }
    return result;
  }

  // ---------------------------------------------------------------- 调休

  /// 日期 → `yyyy-MM-dd`。
  static String dateKey(DateTime date) => ScheduleConfig.dateKey(date);

  /// [date] 这一天实际按哪一周、星期几上课（调休 / 停课已展开）。
  static EffectiveDay effectiveDayOf(DateTime date, ScheduleConfig config) {
    final day = DateTime(date.year, date.month, date.day);
    final calendarWeek = rawWeekOf(day, config);
    final o = config.overrideOn(day);
    return EffectiveDay(
      date: day,
      calendarWeek: calendarWeek,
      week: o?.actAsWeek ?? calendarWeek,
      weekday: o?.actAsWeekday ?? day.weekday,
      cancelled: o?.cancelled ?? false,
      override: o,
    );
  }

  // ---------------------------------------------------------------- 课程查询

  /// 某一天的课程（按起始节次升序），调休 / 停课已生效。
  ///
  /// 这是「某天有什么课」的唯一入口：周视图、小组件快照、上课提醒都走这里
  /// （周视图拿 [effectiveDayOf] 自己再分本周 / 非本周）。
  static List<Course> coursesOn(DateTime date, Timetable timetable) =>
      coursesOnEffective(effectiveDayOf(date, timetable.config), timetable);

  /// 按已经展开好的 [EffectiveDay] 取课程。
  static List<Course> coursesOnEffective(
    EffectiveDay day,
    Timetable timetable,
  ) {
    if (day.cancelled || day.week < 1) return <Course>[];
    final list =
        timetable.courses
            .where((c) => c.day == day.weekday && c.isInWeek(day.week))
            .toList()
          ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    return list;
  }

  /// 某一周的课程（周一到周日）。
  static List<Course> coursesInWeek(int week, Timetable timetable) {
    final list = timetable.courses.where((c) => c.isInWeek(week)).toList()
      ..sort((a, b) {
        final d = a.day.compareTo(b.day);
        return d != 0 ? d : a.startPeriod.compareTo(b.startPeriod);
      });
    return list;
  }

  /// 检测同一课表内的时间冲突（同一天、同周、节次区间重叠）。
  static List<(Course, Course)> findConflicts(Timetable timetable) {
    final conflicts = <(Course, Course)>[];
    final courses = timetable.courses;
    for (var i = 0; i < courses.length; i++) {
      for (var j = i + 1; j < courses.length; j++) {
        final a = courses[i];
        final b = courses[j];
        if (a.day != b.day) continue;
        if (a.endPeriod < b.startPeriod || b.endPeriod < a.startPeriod) {
          continue;
        }
        final shared = a.weeks.toSet().intersection(b.weeks.toSet());
        if (shared.isEmpty) continue;
        conflicts.add((a, b));
      }
    }
    return conflicts;
  }
}
