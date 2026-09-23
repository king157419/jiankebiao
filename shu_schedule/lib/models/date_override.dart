/// 某一个日历日的调休 / 停课规则（学期设置里的「调休 / 停课」）。
///
/// 三种用法，可以组合：
/// - [cancelled] = true：这一天停课，其余字段忽略（例如国庆假期里的工作日）；
/// - [actAsWeekday]：这一天按「星期几」的课表上课（例如国庆后的周六上周一的课）；
/// - [actAsWeek]：这一天按「第几周」的课表上课（例如补某一周的课）。
///
/// 两个 actAs 都为 null 时按日期本身的周次 / 星期；只给 [actAsWeekday] 时周次沿用
/// 这一天自己所在的周；只给 [actAsWeek] 时星期沿用这一天自己的星期。
class DateOverride {
  /// 这一天停课。
  final bool cancelled;

  /// 按第几周上课（>= 1），null = 用这一天本身所在的周。
  final int? actAsWeek;

  /// 按星期几上课（1..7，1 = 周一），null = 用这一天本身的星期。
  final int? actAsWeekday;

  /// 备注，例如「国庆调休」。
  final String? note;

  const DateOverride({
    this.cancelled = false,
    this.actAsWeek,
    this.actAsWeekday,
    this.note,
  });

  /// 停课。
  const DateOverride.cancelled({String? note})
    : this(cancelled: true, note: note);

  /// 按另一个星期（可选另一周）上课。
  const DateOverride.actAs({int? week, int? weekday, String? note})
    : this(actAsWeek: week, actAsWeekday: weekday, note: note);

  /// 是否真的改变了这一天的课程（只写了备注的不算）。
  bool get changesSchedule =>
      cancelled || actAsWeek != null || actAsWeekday != null;

  /// 界面上的短标签：「停课」/「调休」；不改变课程时为 null。
  String? get shortLabel {
    if (cancelled) return '停课';
    if (actAsWeek != null || actAsWeekday != null) return '调休';
    return null;
  }

  DateOverride copyWith({
    bool? cancelled,
    int? actAsWeek,
    int? actAsWeekday,
    String? note,
    bool clearActAsWeek = false,
    bool clearActAsWeekday = false,
    bool clearNote = false,
  }) => DateOverride(
    cancelled: cancelled ?? this.cancelled,
    actAsWeek: clearActAsWeek ? null : (actAsWeek ?? this.actAsWeek),
    actAsWeekday: clearActAsWeekday
        ? null
        : (actAsWeekday ?? this.actAsWeekday),
    note: clearNote ? null : (note ?? this.note),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'cancelled': cancelled,
    'actAsWeek': actAsWeek,
    'actAsWeekday': actAsWeekday,
    'note': note,
  };

  /// 容错解析：类型不对 / 越界的字段一律当 null。
  factory DateOverride.fromJson(Map<String, dynamic> json) {
    final week = _asInt(json['actAsWeek']);
    final weekday = _asInt(json['actAsWeekday']);
    final note = json['note'];
    return DateOverride(
      cancelled: json['cancelled'] == true,
      actAsWeek: week != null && week >= 1 && week <= 60 ? week : null,
      actAsWeekday: weekday != null && weekday >= 1 && weekday <= 7
          ? weekday
          : null,
      note: note is String && note.trim().isNotEmpty ? note : null,
    );
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DateOverride &&
      other.cancelled == cancelled &&
      other.actAsWeek == actAsWeek &&
      other.actAsWeekday == actAsWeekday &&
      other.note == note;

  @override
  int get hashCode => Object.hash(cancelled, actAsWeek, actAsWeekday, note);

  @override
  String toString() =>
      'DateOverride(cancelled: $cancelled, week: $actAsWeek, '
      'weekday: $actAsWeekday, note: $note)';
}
