import '../../models/course.dart';

/// 课程编辑页用到的纯逻辑：字段校验、周次快捷方案、默认配色。
///
/// 抽成独立文件是为了能不启动 UI 就单测。
class CourseForm {
  CourseForm._();

  /// 课程名必填。
  static String? validateName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '请填写课程名';
    if (raw.trim().length > 40) return '课程名太长了（最多 40 字）';
    return null;
  }

  /// 节次范围校验：`1 <= start <= end <= periodCount`。
  static String? validatePeriodRange(int start, int end, int periodCount) {
    if (periodCount < 1) return '当前作息表没有节次，请先在设置里添加';
    if (start < 1 || start > periodCount) return '起始节次必须在 1-$periodCount 之间';
    if (end < 1 || end > periodCount) return '结束节次必须在 1-$periodCount 之间';
    if (start > end) return '结束节次不能早于起始节次';
    return null;
  }

  /// 星期校验：1..7。
  static String? validateDay(int day) {
    if (day < 1 || day > 7) return '星期必须在周一到周日之间';
    return null;
  }

  /// 至少选一周。
  static String? validateWeeks(List<int> weeks) {
    if (weeks.isEmpty) return '请至少选择一周';
    return null;
  }

  /// 整体校验，返回第一条错误；全部通过返回 null。
  static String? validateAll({
    required String? name,
    required int day,
    required int startPeriod,
    required int endPeriod,
    required int periodCount,
    required List<int> weeks,
  }) {
    return validateName(name) ??
        validateDay(day) ??
        validatePeriodRange(startPeriod, endPeriod, periodCount) ??
        validateWeeks(weeks);
  }

  // ------------------------------------------------------------ 周次快捷方案

  /// 全部周。
  static List<int> allWeeks(int totalWeeks) => <int>[
    for (var w = 1; w <= totalWeeks; w++) w,
  ];

  /// 单周。
  static List<int> oddWeeks(int totalWeeks) =>
      allWeeks(totalWeeks).where((w) => w.isOdd).toList();

  /// 双周。
  static List<int> evenWeeks(int totalWeeks) =>
      allWeeks(totalWeeks).where((w) => w.isEven).toList();

  /// 前半学期。
  static List<int> firstHalfWeeks(int totalWeeks) {
    final half = (totalWeeks / 2).ceil();
    return <int>[for (var w = 1; w <= half; w++) w];
  }

  /// 后半学期。
  static List<int> secondHalfWeeks(int totalWeeks) {
    final half = (totalWeeks / 2).ceil();
    return <int>[for (var w = half + 1; w <= totalWeeks; w++) w];
  }

  /// 按课程名哈希出一个稳定的默认色槽（0..9），同名课程颜色始终一致。
  static int defaultColorIndex(String name, {int slots = 10}) {
    if (slots < 1) return 0;
    if (name.isEmpty) return 0;
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % slots;
  }

  /// 构造 / 更新课程时统一做一次规范化（周次去重升序、节次纠正）。
  static Course normalize(Course course, {int? periodCount}) {
    var start = course.startPeriod < 1 ? 1 : course.startPeriod;
    var end = course.endPeriod < start ? start : course.endPeriod;
    if (periodCount != null && periodCount > 0) {
      if (start > periodCount) start = periodCount;
      if (end > periodCount) end = periodCount;
    }
    return course.copyWith(
      name: course.name.trim(),
      day: course.day.clamp(1, 7),
      startPeriod: start,
      endPeriod: end,
      weeks: Course.normalizeWeeks(course.weeks),
      colorIndex: course.colorIndex.clamp(0, 9),
    );
  }

  // ------------------------------------------------------------ 录入提效

  /// 「复制到其他星期」：以 [base] 为模板，给 [days] 里每个星期各生成一门课。
  ///
  /// - 副本和 [base] 共用 [groupId]（同一门课的多个时段，改色会同步）；
  /// - 副本的 id 由 [newId] 生成，`externalKey` 清空（它只属于导入来的那一条），
  ///   来源标成 `manual`；
  /// - 和 [base] 同一天的、重复的、越界的星期都会被跳过。
  static List<Course> copiesToDays(
    Course base,
    Iterable<int> days, {
    required String groupId,
    required String Function() newId,
  }) {
    final seen = <int>{base.day};
    final result = <Course>[];
    for (final d in days) {
      if (d < 1 || d > 7 || !seen.add(d)) continue;
      result.add(
        base.copyWith(
          id: newId(),
          day: d,
          groupId: groupId,
          source: 'manual',
          clearExternalKey: true,
        ),
      );
    }
    return result;
  }

  /// 教师 / 地点的历史补全候选：当前课表里已有的值，去掉首尾空白后去重，
  /// 按出现次数降序（同次数按首次出现顺序）。
  static List<String> historyValues(
    Iterable<Course> courses,
    String? Function(Course) field,
  ) {
    final counts = <String, int>{};
    for (final c in courses) {
      final v = field(c)?.trim();
      if (v == null || v.isEmpty) continue;
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final order = counts.keys.toList();
    final entries = order.asMap().entries.toList()
      ..sort((a, b) {
        final byCount = counts[b.value]!.compareTo(counts[a.value]!);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return <String>[for (final e in entries) e.value];
  }

  /// 按输入过滤补全候选：输入为空不给候选（不打扰）；
  /// 包含输入（忽略大小写）的保留，和输入完全相同的去掉，最多 [limit] 条，
  /// 以输入开头的排在前面。
  static List<String> matchSuggestions(
    List<String> options,
    String query, {
    int limit = 8,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <String>[];
    final prefix = <String>[];
    final contains = <String>[];
    for (final o in options) {
      final lower = o.toLowerCase();
      if (lower == q) continue;
      if (lower.startsWith(q)) {
        prefix.add(o);
      } else if (lower.contains(q)) {
        contains.add(o);
      }
    }
    return <String>[...prefix, ...contains].take(limit).toList();
  }
}
