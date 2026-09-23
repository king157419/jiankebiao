/// 一节课的时间段，例如第 1 节 08:00-08:45。
class PeriodTime {
  /// 节次序号，从 1 开始。
  final int index;

  /// 开始时间，"HH:mm" 24 小时制。
  final String start;

  /// 结束时间，"HH:mm" 24 小时制。
  final String end;

  const PeriodTime({
    required this.index,
    required this.start,
    required this.end,
  });

  PeriodTime copyWith({int? index, String? start, String? end}) => PeriodTime(
    index: index ?? this.index,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  /// 开始时间的「当天分钟数」，解析失败返回 0。
  int get startMinutes => _toMinutes(start);

  /// 结束时间的「当天分钟数」，解析失败返回 0。
  int get endMinutes => _toMinutes(end);

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0].trim()) ?? 0;
    final m = int.tryParse(parts[1].trim()) ?? 0;
    return h.clamp(0, 23) * 60 + m.clamp(0, 59);
  }

  Map<String, dynamic> toJson() => {'index': index, 'start': start, 'end': end};

  factory PeriodTime.fromJson(Map<String, dynamic> json) => PeriodTime(
    index: _asInt(json['index'], 1),
    start: _asTime(json['start'], '08:00'),
    end: _asTime(json['end'], '08:45'),
  );

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static String _asTime(Object? v, String fallback) {
    if (v is! String) return fallback;
    final m = RegExp(r'^\s*(\d{1,2}):(\d{1,2})\s*$').firstMatch(v);
    if (m == null) return fallback;
    final h = int.parse(m.group(1)!).clamp(0, 23);
    final mi = int.parse(m.group(2)!).clamp(0, 59);
    return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => 'PeriodTime($index, $start-$end)';

  @override
  bool operator ==(Object other) =>
      other is PeriodTime &&
      other.index == index &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(index, start, end);
}
