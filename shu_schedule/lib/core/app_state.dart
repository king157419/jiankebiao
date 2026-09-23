import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/course.dart';
import '../models/period_time.dart';
import '../models/schedule_config.dart';
import '../models/timetable.dart';
import 'presets.dart';
import 'storage.dart';

/// 全局应用状态。所有写操作都会在变更后自动 [save]。
class AppState extends ChangeNotifier {
  static const Uuid _uuid = Uuid();

  List<Timetable> _timetables = <Timetable>[];
  AppSettings _settings = AppSettings.defaults();
  bool _loaded = false;
  List<String> _warnings = <String>[];

  /// 是否已完成首次加载。
  bool get isLoaded => _loaded;

  /// 加载时遇到并已自动修复的问题。
  List<String> get warnings => List<String>.unmodifiable(_warnings);

  List<Timetable> get timetables => List<Timetable>.unmodifiable(_timetables);

  AppSettings get settings => _settings;

  /// 当前课表；一张都没有时返回 null。
  Timetable? get currentTimetable {
    if (_timetables.isEmpty) return null;
    for (final t in _timetables) {
      if (t.id == _settings.currentTimetableId) return t;
    }
    return _timetables.first;
  }

  /// 当前课表的配置；没有课表时返回内置默认配置。
  ScheduleConfig get currentConfig =>
      currentTimetable?.config ?? ScheduleConfig.defaults();

  // ------------------------------------------------------------ 加载 / 保存

  Future<void> load() async {
    final snapshot = await Storage.load();
    _timetables = snapshot.timetables;
    _settings = snapshot.settings;
    _warnings = snapshot.warnings;
    _loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    await Storage.save(_timetables, _settings);
  }

  Future<void> _commit() async {
    notifyListeners();
    await save();
  }

  // -------------------------------------------------------------- 课表管理

  /// 新建一张空课表并切换过去，返回新课表。
  Future<Timetable> createTimetable({
    String name = '我的课表',
    ScheduleConfig? config,
  }) async {
    final tt = Timetable(
      id: _uuid.v4(),
      name: name,
      config: config ?? ScheduleConfig.defaults(),
    );
    _timetables.add(tt);
    _settings.currentTimetableId = tt.id;
    await _commit();
    return tt;
  }

  /// 直接加入一张已经构造好的课表（导入 / 备份恢复用）。
  Future<void> addTimetable(Timetable timetable, {bool switchTo = true}) async {
    _timetables.add(timetable);
    if (switchTo) _settings.currentTimetableId = timetable.id;
    await _commit();
  }

  Future<void> renameTimetable(String id, String name) async {
    final tt = _byId(id);
    if (tt == null) return;
    tt.name = name;
    await _commit();
  }

  Future<void> deleteTimetable(String id) async {
    _timetables.removeWhere((t) => t.id == id);
    if (_settings.currentTimetableId == id) {
      _settings.currentTimetableId = _timetables.isEmpty
          ? ''
          : _timetables.first.id;
    }
    await _commit();
  }

  Future<void> switchTimetable(String id) async {
    if (_byId(id) == null) return;
    _settings.currentTimetableId = id;
    await _commit();
  }

  /// 把一次教务导入写进课表，只保存一次。
  ///
  /// [overwriteId] 指向一张存在的课表时覆盖它：换掉课程、配置和导入元数据，
  /// **保留 `Timetable.name`**（用户起的名字）；否则新建一张名为 [name] 的课表并切换过去。
  Future<Timetable> applyImport({
    String? overwriteId,
    required String name,
    required List<Course> courses,
    required ScheduleConfig config,
    String? schoolId,
    String? systemType,
    String? termCode,
    DateTime? importedAt,
  }) async {
    final existing = overwriteId == null ? null : _byId(overwriteId);
    final Timetable tt;
    if (existing != null) {
      existing
        ..courses = List<Course>.from(courses)
        ..config = config
        ..schoolId = schoolId
        ..systemType = systemType
        ..termCode = termCode
        ..importedAt = importedAt;
      tt = existing;
    } else {
      tt = Timetable(
        id: _uuid.v4(),
        name: name,
        config: config,
        courses: List<Course>.from(courses),
        schoolId: schoolId,
        systemType: systemType,
        termCode: termCode,
        importedAt: importedAt,
      );
      _timetables.add(tt);
      _settings.currentTimetableId = tt.id;
    }
    await _commit();
    return tt;
  }

  /// 用新的课程列表整体覆盖某张课表（导入「覆盖当前课表」用）。
  Future<void> replaceCourses(String timetableId, List<Course> courses) async {
    final tt = _byId(timetableId);
    if (tt == null) return;
    tt.courses = List<Course>.from(courses);
    await _commit();
  }

  // -------------------------------------------------------------- 课程管理

  /// 添加一门课；未指定 id 时自动生成。
  ///
  /// 一张课表都没有时会自动新建一张默认课表再放进去
  /// —— 冷启动空状态的「手动添加」走的就是这条路，
  /// 不自动建表的话用户点了保存却什么都不会发生（课程被静默丢弃）。
  Future<Course?> addCourse(Course course, {String? timetableId}) async {
    var tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    tt ??= await createTimetable();
    final withId = course.id.isEmpty ? course.copyWith(id: _uuid.v4()) : course;
    tt.courses.add(withId);
    await _commit();
    return withId;
  }

  /// 一次加入多门课、只保存一次（「复制到其他星期」用）。
  ///
  /// 没有 id 的课自动生成；一张课表都没有时和 [addCourse] 一样先建一张默认课表。
  Future<List<Course>> addCourses(
    List<Course> courses, {
    String? timetableId,
  }) async {
    if (courses.isEmpty) return const <Course>[];
    var tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    tt ??= await createTimetable();
    final added = <Course>[
      for (final c in courses) c.id.isEmpty ? c.copyWith(id: _uuid.v4()) : c,
    ];
    tt.courses.addAll(added);
    await _commit();
    return added;
  }

  /// 更新一门课。
  ///
  /// [syncGroupColor] 为 true（默认）且这门课有 [Course.groupId] 时，
  /// 颜色改动会同步到同组（同一门课的其他时段）的所有课程。
  Future<void> updateCourse(
    Course course, {
    String? timetableId,
    bool syncGroupColor = true,
  }) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    final index = tt.courses.indexWhere((c) => c.id == course.id);
    if (index < 0) return;
    final previous = tt.courses[index];
    tt.courses[index] = course;
    final group = course.groupId;
    if (syncGroupColor &&
        group != null &&
        previous.colorIndex != course.colorIndex) {
      for (var i = 0; i < tt.courses.length; i++) {
        final c = tt.courses[i];
        if (i != index && c.groupId == group) {
          tt.courses[i] = c.copyWith(colorIndex: course.colorIndex);
        }
      }
    }
    await _commit();
  }

  /// 同一张课表里和 [groupId] 同组的所有课程（同一门课的各个时段）。
  List<Course> coursesInGroup(String groupId, {String? timetableId}) {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return const <Course>[];
    return tt.courses.where((c) => c.groupId == groupId).toList();
  }

  Future<void> deleteCourse(String courseId, {String? timetableId}) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    tt.courses.removeWhere((c) => c.id == courseId);
    await _commit();
  }

  /// 生成一个新的课程 id（供 UI 在构造 Course 时使用）。
  String newId() => _uuid.v4();

  // -------------------------------------------------------------- 配置管理

  Future<void> updateConfig(
    ScheduleConfig config, {
    String? timetableId,
  }) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    tt.config = config;
    await _commit();
  }

  /// 设置（[value] 非 null）或删除（[value] 为 null）某一天的调休 / 停课。
  Future<void> setDateOverride(
    DateTime date,
    DateOverride? value, {
    String? timetableId,
  }) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    tt.config = tt.config.withOverride(date, value);
    await _commit();
  }

  /// 修改休息带：null = 按作息自动推导，列表 = 手动指定（[PeriodTime.index]）。
  Future<void> setBreakAfter(
    List<int>? breakAfter, {
    String? timetableId,
  }) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    tt.config = breakAfter == null
        ? tt.config.copyWith(clearBreakAfter: true)
        : tt.config.copyWith(breakAfter: breakAfter);
    await _commit();
  }

  /// 修改作息表。
  Future<void> updatePeriods(List<PeriodTime> periods) async {
    final tt = currentTimetable;
    if (tt == null) return;
    tt.config.periods = List<PeriodTime>.from(periods)
      ..sort((a, b) => a.index.compareTo(b.index));
    await _commit();
  }

  /// 一键恢复内置的 12 节示例作息。
  Future<void> resetPeriodsToDefault() async {
    await updatePeriods(List<PeriodTime>.from(defaultPeriods));
  }

  // -------------------------------------------------------------- 设置管理

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    await _commit();
  }

  Future<void> setThemeId(String themeId) async {
    _settings.themeId = themeId;
    await _commit();
  }

  Future<void> setShowNonCurrentWeekCourses(bool value) async {
    _settings.showNonCurrentWeekCourses = value;
    await _commit();
  }

  Future<void> setShowTimeInGrid(bool value) async {
    _settings.showTimeInGrid = value;
    await _commit();
  }

  Future<void> setRememberEduLogin(bool value) async {
    _settings.rememberEduLogin = value;
    await _commit();
  }

  /// 记录用户同意了第 [version] 版隐私说明。
  Future<void> acceptPrivacy(int version) async {
    _settings.privacyAcceptedVersion = version;
    await _commit();
  }

  /// 记录一次检查更新的时间（每天最多自动查一次靠它）。
  Future<void> setLastUpdateCheck(DateTime time) async {
    _settings.lastUpdateCheck = time;
    await _commit();
  }

  /// 备份恢复：整体替换所有数据。
  ///
  /// 覆盖前会把现有 `timetables.json` 另存一份
  /// （`timetables.json.before-restore-<时间戳>`），恢复错了还能手工捞回来。
  /// 同时修掉备份里可能存在的重复/缺失 id，并保证 `currentTimetableId` 不悬空。
  Future<void> restoreFrom(StorageSnapshot snapshot) async {
    final restoreWarnings = <String>[...snapshot.warnings];
    final backup = await Storage.backupBeforeRestore();
    if (backup != null) {
      restoreWarnings.add('恢复前的旧数据已备份到 $backup。');
    }

    final restored = List<Timetable>.from(snapshot.timetables);
    Storage.normalizeIds(restored, restoreWarnings);

    // 隐私同意 / 检查更新时间是「这台手机上的这个 App」的状态，不跟着备份走：
    // 恢复一份旧备份不应该让用户再同意一次隐私说明，也不应该重置更新节流。
    final keepPrivacy = _settings.privacyAcceptedVersion;
    final keepLastCheck = _settings.lastUpdateCheck;
    _timetables = restored;
    _settings = snapshot.settings;
    if (keepPrivacy > _settings.privacyAcceptedVersion) {
      _settings.privacyAcceptedVersion = keepPrivacy;
    }
    _settings.lastUpdateCheck = keepLastCheck ?? _settings.lastUpdateCheck;
    if (_timetables.isEmpty) {
      _settings.currentTimetableId = '';
    } else if (!_timetables.any((t) => t.id == _settings.currentTimetableId)) {
      _settings.currentTimetableId = _timetables.first.id;
    }
    _warnings = restoreWarnings;
    await _commit();
  }

  Timetable? _byId(String id) {
    if (id.isEmpty) return null;
    for (final t in _timetables) {
      if (t.id == id) return t;
    }
    return null;
  }
}
