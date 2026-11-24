import 'course.dart';
import 'schedule_config.dart';

/// 一张完整课表：配置 + 课程列表 + 导入元数据。
class Timetable {
  String id;
  String name;
  ScheduleConfig config;
  List<Course> courses;

  /// 学校 id（对应 `SchoolAdapter.id`，例如 `shu`），手动建的课表为 null。
  /// v1.3.0 新增。
  String? schoolId;

  /// 教务系统类型（例如 `zfsoft`），手动建的课表为 null。v1.3.0 新增。
  String? systemType;

  /// 教务里的学年学期代码（例如 `2026-2027-1`），可空。v1.3.0 新增。
  String? termCode;

  /// 最近一次从教务导入的时间，可空。v1.3.0 新增。
  DateTime? importedAt;

  Timetable({
    required this.id,
    required this.name,
    required this.config,
    List<Course>? courses,
    this.schoolId,
    this.systemType,
    this.termCode,
    this.importedAt,
  }) : courses = courses ?? <Course>[];

  /// 新建一张使用默认作息与默认学期的空课表。
  factory Timetable.empty({String? id, String name = '我的课表'}) {
    return Timetable(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      config: ScheduleConfig.defaults(),
      courses: <Course>[],
    );
  }

  /// 来源标记：`'<systemType>-<schoolId>'`，两者都有时才有值。
  String? get sourceTag => (systemType != null && schoolId != null)
      ? sourceTagOf(systemType!, schoolId!)
      : null;

  /// 来源标记的唯一拼法。导入时写进 `Course.source`，课表上由 [sourceTag] 推出。
  static String sourceTagOf(String systemType, String schoolId) =>
      '$systemType-$schoolId';

  /// 按「同名 + 同教师」去重后的课程门数（同一门课一周多个时段只算 1 门，PLAN-1.5 R1-13）。
  static int uniqueCourseCount(Iterable<Course> courses) {
    final seen = <String>{};
    for (final c in courses) {
      final name = c.name.trim();
      final teacher = (c.teacher ?? '').trim();
      seen.add('$name\u0000$teacher');
    }
    return seen.length;
  }

  /// 「x 门课」展示文案：同名 + 同教师算一门；时段条数多于门数时补上「（每周 y 节）」。
  static String formatCourseCount(List<Course> courses) {
    if (courses.isEmpty) return '0 门课';
    final unique = uniqueCourseCount(courses);
    final sessions = courses.length;
    return sessions > unique ? '$unique 门课（每周 $sessions 节）' : '$unique 门课';
  }

  /// 当前课表的课程数量文案（见 [formatCourseCount]）。
  String get courseCountText => formatCourseCount(courses);

  Timetable copyWith({
    String? id,
    String? name,
    ScheduleConfig? config,
    List<Course>? courses,
    String? schoolId,
    String? systemType,
    String? termCode,
    DateTime? importedAt,
    bool clearImportMeta = false,
  }) => Timetable(
    id: id ?? this.id,
    name: name ?? this.name,
    config: config ?? this.config.copyWith(),
    courses: courses ?? List<Course>.from(this.courses),
    schoolId: clearImportMeta ? null : (schoolId ?? this.schoolId),
    systemType: clearImportMeta ? null : (systemType ?? this.systemType),
    termCode: clearImportMeta ? null : (termCode ?? this.termCode),
    importedAt: clearImportMeta ? null : (importedAt ?? this.importedAt),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'config': config.toJson(),
    'courses': courses.map((c) => c.toJson()).toList(),
    'schoolId': schoolId,
    'systemType': systemType,
    'termCode': termCode,
    'importedAt': importedAt?.toIso8601String(),
  };

  factory Timetable.fromJson(Map<String, dynamic> json) {
    final migrated = migrateLegacyJson(json);
    final rawCourses = migrated['courses'];
    final courses = rawCourses is List
        ? rawCourses
              .whereType<Map>()
              .map((e) => Course.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <Course>[];
    final rawConfig = migrated['config'];
    final importedAt = migrated['importedAt'];
    return Timetable(
      id: migrated['id'] is String && (migrated['id'] as String).isNotEmpty
          ? migrated['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      name: migrated['name'] is String ? migrated['name'] as String : '我的课表',
      config: rawConfig is Map
          ? ScheduleConfig.fromJson(Map<String, dynamic>.from(rawConfig))
          : ScheduleConfig.defaults(),
      courses: courses,
      schoolId: _asNullableString(migrated['schoolId']),
      systemType: _asNullableString(migrated['systemType']),
      termCode: _asNullableString(migrated['termCode']),
      importedAt: importedAt is String ? DateTime.tryParse(importedAt) : null,
    );
  }

  /// 旧来源标记 → (systemType, schoolId)。v1.2.0 及以前只有一个来源（`zfsoft-shu`）。
  static const Map<String, (String, String)> legacySourceTags =
      <String, (String, String)>{'zfsoft-shu': ('zfsoft', 'shu')};

  /// 把 v1.2.0 及以前的课表 JSON 补成 v1.3.0 结构（纯函数，返回新 Map）。
  ///
  /// 只在 `schoolId` / `systemType` **两个 key 都不存在**时才推断：
  /// 课程里出现过已知的旧来源标记（`zfsoft-shu`）就把课表标成对应学校。
  /// 新版本写出的 JSON 总带这两个 key（哪怕是 null），所以这个函数是幂等的，
  /// 不会把用户后来手动建的课表误标成导入课表。
  static Map<String, dynamic> migrateLegacyJson(Map<String, dynamic> json) {
    if (json.containsKey('schoolId') || json.containsKey('systemType')) {
      return json;
    }
    final result = Map<String, dynamic>.from(json);
    final rawCourses = json['courses'];
    if (rawCourses is List) {
      for (final c in rawCourses) {
        if (c is! Map) continue;
        final hit = legacySourceTags[c['source']];
        if (hit != null) {
          result['systemType'] = hit.$1;
          result['schoolId'] = hit.$2;
          break;
        }
      }
    }
    return result;
  }

  static String? _asNullableString(Object? v) {
    if (v is String && v.trim().isNotEmpty) return v;
    return null;
  }

  @override
  String toString() => 'Timetable($name, ${courses.length} 门课)';
}
