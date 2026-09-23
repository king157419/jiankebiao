import '../../models/period_time.dart';

/// 作息编辑页用到的纯逻辑：单节时间校验、增删节次后的重新编号。
class PeriodForm {
  PeriodForm._();

  /// 校验把第 [position]（0 基）节改成 [start]-[end] 是否合法。
  ///
  /// 规则：结束必须晚于开始；不能与上一节、下一节重叠。
  /// 合法返回 null，否则返回中文错误文案。
  static String? validateEdit(
    List<PeriodTime> periods,
    int position,
    String start,
    String end,
  ) {
    if (position < 0 || position >= periods.length) return '节次不存在';
    final candidate = PeriodTime(
      index: periods[position].index,
      start: start,
      end: end,
    );
    if (candidate.endMinutes <= candidate.startMinutes) {
      return '结束时间必须晚于开始时间';
    }
    if (position > 0) {
      final prev = periods[position - 1];
      if (candidate.startMinutes < prev.endMinutes) {
        return '与第 ${prev.index} 节（${prev.start}-${prev.end}）重叠';
      }
    }
    if (position < periods.length - 1) {
      final next = periods[position + 1];
      if (candidate.endMinutes > next.startMinutes) {
        return '与第 ${next.index} 节（${next.start}-${next.end}）重叠';
      }
    }
    return null;
  }

  /// 应用一次合法的编辑，返回新的作息表（原列表不变）。
  static List<PeriodTime> applyEdit(
    List<PeriodTime> periods,
    int position,
    String start,
    String end,
  ) {
    final copy = List<PeriodTime>.from(periods);
    copy[position] = copy[position].copyWith(start: start, end: end);
    return copy;
  }

  /// 在末尾追加一节：起点取最后一节结束后 [gapMinutes] 分钟，时长沿用最后一节。
  static List<PeriodTime> appendPeriod(
    List<PeriodTime> periods, {
    int gapMinutes = 10,
  }) {
    if (periods.isEmpty) {
      return <PeriodTime>[
        const PeriodTime(index: 1, start: '08:00', end: '08:45'),
      ];
    }
    final last = periods.last;
    final duration = (last.endMinutes - last.startMinutes).clamp(5, 24 * 60);
    var startMinutes = last.endMinutes + gapMinutes;
    var endMinutes = startMinutes + duration;
    if (endMinutes > 23 * 60 + 59) {
      endMinutes = 23 * 60 + 59;
      if (startMinutes >= endMinutes) startMinutes = endMinutes - 5;
    }
    return <PeriodTime>[
      ...periods,
      PeriodTime(
        index: last.index + 1,
        start: formatMinutes(startMinutes),
        end: formatMinutes(endMinutes),
      ),
    ];
  }

  /// 删除末尾一节；只剩一节时不允许删除，返回原列表。
  static List<PeriodTime> removeLast(List<PeriodTime> periods) {
    if (periods.length <= 1) return periods;
    return periods.sublist(0, periods.length - 1);
  }

  /// 把 index 重排成 1..n，保证连续。
  static List<PeriodTime> renumber(List<PeriodTime> periods) => <PeriodTime>[
    for (var i = 0; i < periods.length; i++) periods[i].copyWith(index: i + 1),
  ];

  /// 分钟数 → "HH:mm"。
  static String formatMinutes(int minutes) {
    final m = minutes.clamp(0, 24 * 60 - 1);
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }
}
