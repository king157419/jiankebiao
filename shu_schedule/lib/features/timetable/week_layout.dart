import '../../core/schedule_utils.dart';
import '../../models/period_time.dart';
import '../../models/schedule_config.dart';

/// 休息带的种类，决定高度和日期列里的文字。
enum BreakKind {
  /// 午间（间隔中点在 11:00 到 15:00 之间）。
  noon,

  /// 傍晚 / 晚间（间隔中点在 15:00 及以后）。
  evening,

  /// 其他（上午的大课间，或作息时间写得不规范）。
  other,
}

/// 周课表网格的几何计算（纯函数，不依赖 Widget）。
///
/// 约定：`position` 是节次在作息表里的下标（0 基），`PeriodTime.index` 只用于显示。
///
/// 休息带不再写死在第 4、8 节后（v1.3.0）：默认按作息推导——相邻两节间隔
/// >= 40 分钟就画一条（`ScheduleUtils.breakAfterIndices`），
/// `ScheduleConfig.breakAfter` 可以手动覆盖。休息带不计入节数。
class WeekLayout {
  /// 每节基础高度（dp）。
  final double periodHeight;

  /// 午间休息带高度。
  final double noonBreakHeight;

  /// 晚间休息带高度（[BreakKind.other] 也用这个高度）。
  final double eveningBreakHeight;

  /// 按 index 升序的作息表。
  final List<PeriodTime> periods;

  /// 在哪些 position 之后画休息带（升序，不含最后一节）。
  final List<int> breakAfterPositions;

  WeekLayout._(
    this.periods,
    this.breakAfterPositions, {
    required this.periodHeight,
    required this.noonBreakHeight,
    required this.eveningBreakHeight,
  });

  /// [breakAfterIndices] 是 [PeriodTime.index] 列表；为 null 时按 [periods]
  /// 的时间自动推导（>= 40 分钟画带）。
  factory WeekLayout({
    required List<PeriodTime> periods,
    double periodHeight = 58,
    double noonBreakHeight = 28,
    double eveningBreakHeight = 24,
    List<int>? breakAfterIndices,
  }) {
    final sorted = List<PeriodTime>.unmodifiable(
      List<PeriodTime>.from(periods)
        ..sort((a, b) => a.index.compareTo(b.index)),
    );
    return WeekLayout._(
      sorted,
      _resolveBreaks(
        sorted,
        breakAfterIndices ?? ScheduleUtils.autoBreakAfterIndices(sorted),
      ),
      periodHeight: periodHeight,
      noonBreakHeight: noonBreakHeight,
      eveningBreakHeight: eveningBreakHeight,
    );
  }

  factory WeekLayout.of(ScheduleConfig config, {double periodHeight = 58}) {
    return WeekLayout(
      periods: config.periods,
      periodHeight: periodHeight,
      breakAfterIndices: ScheduleUtils.breakAfterIndices(config),
    );
  }

  static List<int> _resolveBreaks(List<PeriodTime> sorted, List<int> indices) {
    final result = <int>{};
    for (final index in indices) {
      for (var i = 0; i < sorted.length - 1; i++) {
        if (sorted[i].index == index) result.add(i);
      }
    }
    return List<int>.unmodifiable(result.toList()..sort());
  }

  int get count => periods.length;

  /// 该位置之后是否要画休息带（后面还有节次才画）。
  bool hasBreakAfter(int position) => breakAfterPositions.contains(position);

  /// [position] 之后那条休息带的种类；没有休息带返回 null。
  BreakKind? breakKindAfter(int position) {
    if (!hasBreakAfter(position)) return null;
    final end = periods[position].endMinutes;
    final start = periods[position + 1].startMinutes;
    if (start <= end) return BreakKind.other;
    final mid = (end + start) ~/ 2;
    if (mid >= 15 * 60) return BreakKind.evening;
    if (mid >= 11 * 60) return BreakKind.noon;
    return BreakKind.other;
  }

  /// 休息带的文字：午间休息 / 晚间休息 / 休息。
  String? breakLabelAfter(int position) {
    switch (breakKindAfter(position)) {
      case BreakKind.noon:
        return '午间休息';
      case BreakKind.evening:
        return '晚间休息';
      case BreakKind.other:
        return '休息';
      case null:
        return null;
    }
  }

  double breakHeightAfter(int position) {
    switch (breakKindAfter(position)) {
      case BreakKind.noon:
        return noonBreakHeight;
      case BreakKind.evening:
      case BreakKind.other:
        return eveningBreakHeight;
      case null:
        return 0;
    }
  }

  /// position 对应的顶部偏移。
  double topOf(int position) {
    var top = 0.0;
    for (var i = 0; i < position && i < count; i++) {
      top += periodHeight;
      if (hasBreakAfter(i)) top += breakHeightAfter(i);
    }
    return top;
  }

  /// 整张网格的高度。
  double get totalHeight => count == 0 ? 0 : topOf(count - 1) + periodHeight;

  /// 把 `PeriodTime.index` 换算成 position；找不到返回 -1。
  int positionOfIndex(int periodIndex) {
    for (var i = 0; i < periods.length; i++) {
      if (periods[i].index == periodIndex) return i;
    }
    return -1;
  }

  /// 把跨休息带的课程拆成若干段（每段内部没有休息带）。
  ///
  /// 例如默认 12 节作息下 3-6 节会拆成 `[(2,3), (4,5)]`（position 表示）。
  List<(int, int)> segmentsOf(int startPosition, int endPosition) {
    if (count == 0) return const <(int, int)>[];
    var s = startPosition.clamp(0, count - 1);
    final e = endPosition.clamp(s, count - 1);
    final result = <(int, int)>[];
    for (final b in breakAfterPositions) {
      if (s <= b && e > b) {
        result.add((s, b));
        s = b + 1;
      }
    }
    result.add((s, e));
    return result;
  }

  /// 一段 [start]..[end]（position）的矩形高度。
  double heightOfSpan(int start, int end) =>
      topOf(end) + periodHeight - topOf(start);

  /// 当前时刻横线的纵向偏移；课前 / 全天课程结束后返回 null（不画线）。
  double? currentTimeOffset(int minutesOfDay) {
    if (count == 0) return null;
    for (var i = 0; i < count; i++) {
      final p = periods[i];
      if (minutesOfDay < p.startMinutes) {
        if (i == 0) return null; // 第一节课之前不画。
        final prev = periods[i - 1];
        final gapMinutes = p.startMinutes - prev.endMinutes;
        final gapHeight = topOf(i) - (topOf(i - 1) + periodHeight);
        if (gapMinutes <= 0 || gapHeight <= 0) return topOf(i);
        final frac = (minutesOfDay - prev.endMinutes) / gapMinutes;
        return topOf(i - 1) + periodHeight + frac.clamp(0.0, 1.0) * gapHeight;
      }
      if (minutesOfDay <= p.endMinutes) {
        final span = p.endMinutes - p.startMinutes;
        if (span <= 0) return topOf(i);
        final frac = (minutesOfDay - p.startMinutes) / span;
        return topOf(i) + frac.clamp(0.0, 1.0) * periodHeight;
      }
    }
    return null; // 最后一节结束之后不画。
  }
}
