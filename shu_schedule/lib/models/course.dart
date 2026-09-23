/// 一门课在课表里的一段安排（同一门课不同周次/不同教室会拆成多条）。
class Course {
  /// 唯一 id。
  String id;

  /// 课程名。
  String name;

  /// 教师，可空。
  String? teacher;

  /// 上课地点，可空。
  String? location;

  /// 星期，1..7，1 = 周一。
  int day;

  /// 起始节次（含）。
  int startPeriod;

  /// 结束节次（含）。
  int endPeriod;

  /// 具体周数列表，例如 [1,2,3,...,16]。
  List<int> weeks;

  /// 主题色索引 0..9，对应 theme.courseColors。
  int colorIndex;

  /// 备注。
  String? note;

  /// 来源：`'manual'` | `'backup'` | 导入来源标记 `'<systemType>-<schoolId>'`
  /// （例如 `'zfsoft-shu'`，见 `Timetable.sourceTagOf`）。
  String source;

  /// 同一门课的多个时段共用的分组 id（例如周二、周四各一次的同一门课），
  /// 可空。编辑其中一条的颜色时，同组的其余几条会跟着改（见
  /// `AppState.updateCourse`）。v1.3.0 新增。
  String? groupId;

  /// 导入来源里的稳定外部键（例如正方的 `kch + jxbmc`），可空。
  /// 用来在重新导入时做差异合并，保留用户改过的颜色和备注。v1.3.0 新增。
  String? externalKey;

  Course({
    required this.id,
    required this.name,
    this.teacher,
    this.location,
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    List<int>? weeks,
    this.colorIndex = 0,
    this.note,
    this.source = 'manual',
    this.groupId,
    this.externalKey,
  }) : weeks = weeks == null ? <int>[] : normalizeWeeks(weeks);

  /// 跨几节。
  int get periodSpan => (endPeriod - startPeriod + 1).clamp(1, 100);

  /// 该课是否在第 [week] 周上。
  bool isInWeek(int week) => weeks.contains(week);

  Course copyWith({
    String? id,
    String? name,
    String? teacher,
    String? location,
    int? day,
    int? startPeriod,
    int? endPeriod,
    List<int>? weeks,
    int? colorIndex,
    String? note,
    String? source,
    String? groupId,
    String? externalKey,
    bool clearTeacher = false,
    bool clearLocation = false,
    bool clearNote = false,
    bool clearGroupId = false,
    bool clearExternalKey = false,
  }) => Course(
    id: id ?? this.id,
    name: name ?? this.name,
    teacher: clearTeacher ? null : (teacher ?? this.teacher),
    location: clearLocation ? null : (location ?? this.location),
    day: day ?? this.day,
    startPeriod: startPeriod ?? this.startPeriod,
    endPeriod: endPeriod ?? this.endPeriod,
    weeks: weeks ?? List<int>.from(this.weeks),
    colorIndex: colorIndex ?? this.colorIndex,
    note: clearNote ? null : (note ?? this.note),
    source: source ?? this.source,
    groupId: clearGroupId ? null : (groupId ?? this.groupId),
    externalKey: clearExternalKey ? null : (externalKey ?? this.externalKey),
  );

  /// 去重 + 升序 + 丢弃非正数。
  static List<int> normalizeWeeks(Iterable<int> input) {
    final set = <int>{};
    for (final w in input) {
      if (w > 0) set.add(w);
    }
    final list = set.toList()..sort();
    return list;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'teacher': teacher,
    'location': location,
    'day': day,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'weeks': weeks,
    'colorIndex': colorIndex,
    'note': note,
    'source': source,
    'groupId': groupId,
    'externalKey': externalKey,
  };

  factory Course.fromJson(Map<String, dynamic> json) {
    final start = _asInt(json['startPeriod'], 1);
    final end = _asInt(json['endPeriod'], start);
    return Course(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] is String ? json['name'] as String : '未命名课程',
      teacher: _asNullableString(json['teacher']),
      location: _asNullableString(json['location']),
      day: _asInt(json['day'], 1).clamp(1, 7),
      startPeriod: start < 1 ? 1 : start,
      endPeriod: end < start ? start : end,
      weeks: _asIntList(json['weeks']),
      colorIndex: _asInt(json['colorIndex'], 0).clamp(0, 9),
      note: _asNullableString(json['note']),
      source: json['source'] is String ? json['source'] as String : 'manual',
      groupId: _asNullableString(json['groupId']),
      externalKey: _asNullableString(json['externalKey']),
    );
  }

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static String? _asNullableString(Object? v) {
    if (v is String && v.trim().isNotEmpty) return v;
    return null;
  }

  static List<int> _asIntList(Object? v) {
    if (v is! List) return <int>[];
    return normalizeWeeks(v.map((e) => _asInt(e, 0)));
  }

  @override
  String toString() =>
      'Course($name, 周$day, $startPeriod-$endPeriod节, '
      '${weeks.length}周)';
}
