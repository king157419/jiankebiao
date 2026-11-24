import 'reminder_settings.dart';

export 'reminder_settings.dart';

/// 全局应用设置。
class AppSettings {
  /// 当前选中的课表 id，空串表示尚未选择。
  String currentTimetableId;

  /// 主题 id，对应 assets/themes/themes.json 里的条目。
  String themeId;

  /// 是否以半透明形式显示非本周课程。
  bool showNonCurrentWeekCourses;

  /// 周表格子里是否显示时间文字。
  bool showTimeInGrid;

  /// 导入完成 / 离开登录页后是否保留教务系统的登录态（Cookie 与网页存储）。
  /// 默认 false：用完就清，拿到手机的人不能直接进教务系统。v1.3.0 新增，
  /// 旧存档没有这个字段 → false（不需要升 [settingsVersion]）。
  bool rememberEduLogin;

  /// 上一次检查更新的时间（本地时间）；null = 从没查过。
  /// 用来保证「每天最多自动查一次」。v1.3.0 新增，旧存档 → null。
  DateTime? lastUpdateCheck;

  /// 上一次联网刷新假日表的时间（本地时间）；null = 从没刷新过。
  /// 用来保证「24 小时内最多自动刷新一次」（`HolidayRepository.refresh`）。
  /// 和 [lastUpdateCheck] 一样是这台手机上的状态，恢复备份时保留设备上的值。
  /// v1.4.0 新增，旧存档 → null（不需要升 [settingsVersion]）。
  DateTime? lastHolidayRefresh;

  /// 上课提醒偏好（总开关、提前分钟、明日预告）。用户偏好，**跟着备份恢复**
  /// （不像 [lastUpdateCheck] 那样保留设备上的值）。v1.4.0 新增，
  /// 旧存档 / 旧备份没有这个字段 → 出厂默认（关闭），不需要升 [settingsVersion]。
  ReminderSettings reminders;

  /// 校历建议面板点过「先不用」或「一键套用」的记录：课表 id →
  /// `'<schoolId>|<term.startDate>|<entriesHash>'`（学期内容指纹 `termKey`）。
  /// 同一所学校同一个学期的条目没变就不再在启动时弹；该学期条目更新了才会再提示。
  /// 用户偏好，跟着备份恢复。v1.5.0 新增，旧存档没有这个字段 → 空表。
  Map<String, String> calendarSuggestionDismissed;

  /// 用户或教务系统已经确认过的开学日期：课表 id → 开学日期 `yyyy-MM-dd`（`dateKey`）。
  /// 确认过这天的课表，启动或假期表更新时校历建议不再提议改开学日期（只提示放假 / 调休）。
  /// 用户偏好，跟着备份恢复。v1.5.0 新增，旧存档没有这个字段 → 空表。
  Map<String, String> termStartConfirmed;

  /// 设置结构的版本号，用来做一次性迁移。
  ///
  /// v1：`showTimeInGrid` 出厂是 true。
  /// v2：改成 false（左边时间列已经写过时刻，格子里再写一遍是噪音），
  ///     老用户升级时跟着改一次，之后用户自己的选择就一直保留。
  int settingsVersion;

  /// 当前的设置结构版本。
  static const int currentVersion = 2;

  AppSettings({
    this.currentTimetableId = '',
    this.themeId = 'default',
    this.showNonCurrentWeekCourses = false,
    this.showTimeInGrid = false,
    this.rememberEduLogin = false,
    this.lastUpdateCheck,
    this.lastHolidayRefresh,
    this.reminders = const ReminderSettings(),
    Map<String, String>? calendarSuggestionDismissed,
    Map<String, String>? termStartConfirmed,
    this.settingsVersion = currentVersion,
  }) : calendarSuggestionDismissed = calendarSuggestionDismissed == null
           ? <String, String>{}
           : Map<String, String>.of(calendarSuggestionDismissed),
       termStartConfirmed = termStartConfirmed == null
           ? <String, String>{}
           : Map<String, String>.of(termStartConfirmed);

  /// 出厂默认设置。
  factory AppSettings.defaults() => AppSettings();

  AppSettings copyWith({
    String? currentTimetableId,
    String? themeId,
    bool? showNonCurrentWeekCourses,
    bool? showTimeInGrid,
    bool? rememberEduLogin,
    DateTime? lastUpdateCheck,
    DateTime? lastHolidayRefresh,
    ReminderSettings? reminders,
    Map<String, String>? calendarSuggestionDismissed,
    Map<String, String>? termStartConfirmed,
    int? settingsVersion,
  }) => AppSettings(
    currentTimetableId: currentTimetableId ?? this.currentTimetableId,
    themeId: themeId ?? this.themeId,
    showNonCurrentWeekCourses:
        showNonCurrentWeekCourses ?? this.showNonCurrentWeekCourses,
    showTimeInGrid: showTimeInGrid ?? this.showTimeInGrid,
    rememberEduLogin: rememberEduLogin ?? this.rememberEduLogin,
    lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
    lastHolidayRefresh: lastHolidayRefresh ?? this.lastHolidayRefresh,
    reminders: reminders ?? this.reminders,
    calendarSuggestionDismissed:
        calendarSuggestionDismissed ?? this.calendarSuggestionDismissed,
    termStartConfirmed: termStartConfirmed ?? this.termStartConfirmed,
    settingsVersion: settingsVersion ?? this.settingsVersion,
  );

  Map<String, dynamic> toJson() => {
    'currentTimetableId': currentTimetableId,
    'themeId': themeId,
    'showNonCurrentWeekCourses': showNonCurrentWeekCourses,
    'showTimeInGrid': showTimeInGrid,
    'rememberEduLogin': rememberEduLogin,
    'lastUpdateCheck': lastUpdateCheck?.toIso8601String(),
    'lastHolidayRefresh': lastHolidayRefresh?.toIso8601String(),
    'reminders': reminders.toJson(),
    'calendarSuggestionDismissed': Map<String, String>.of(
      calendarSuggestionDismissed,
    ),
    'termStartConfirmed': Map<String, String>.of(termStartConfirmed),
    'settingsVersion': settingsVersion,
  };

  /// 存档里的设置结构版本：没有 / 类型不对 → 1（v1 的存档不写这个字段）。
  static int versionOf(Map<String, dynamic> json) {
    final v = json['settingsVersion'];
    if (v is int && v >= 1) return v;
    if (v is num && v >= 1) return v.toInt();
    return 1;
  }

  /// 按版本逐级迁移后构造。读出来的对象永远是 [currentVersion]。
  ///
  /// settings.json 和备份文件里的 `settings` 都走这里，所以备份 v1 → v2
  /// 迁移（`Storage.migrateBackupV1ToV2`）不需要自己处理设置字段。
  ///
  /// 只按键取值，不认识的键直接忽略：v1.3.0–v1.4.0 存档里的
  /// `privacyAcceptedVersion`（v1.5.0 删掉了首启隐私同意）读进来什么都不做，
  /// 下次写盘时自然消失。
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final version = versionOf(json);
    var showTimeInGrid = json['showTimeInGrid'] is bool
        ? json['showTimeInGrid'] as bool
        : false;
    // v1 → v2：不管 v1 里写的是什么，都按新默认值（false）走一次，只迁移这一次。
    if (version < 2) showTimeInGrid = false;
    final lastCheck = json['lastUpdateCheck'];
    final lastHoliday = json['lastHolidayRefresh'];
    return AppSettings(
      currentTimetableId: json['currentTimetableId'] is String
          ? json['currentTimetableId'] as String
          : '',
      themeId:
          json['themeId'] is String && (json['themeId'] as String).isNotEmpty
          ? json['themeId'] as String
          : 'default',
      showNonCurrentWeekCourses: json['showNonCurrentWeekCourses'] is bool
          ? json['showNonCurrentWeekCourses'] as bool
          : false,
      showTimeInGrid: showTimeInGrid,
      rememberEduLogin: json['rememberEduLogin'] is bool
          ? json['rememberEduLogin'] as bool
          : false,
      lastUpdateCheck: lastCheck is String
          ? DateTime.tryParse(lastCheck)
          : null,
      lastHolidayRefresh: lastHoliday is String
          ? DateTime.tryParse(lastHoliday)
          : null,
      reminders: ReminderSettings.fromJson(json['reminders']),
      calendarSuggestionDismissed: _stringMap(
        json['calendarSuggestionDismissed'],
      ),
      termStartConfirmed: _stringMap(json['termStartConfirmed']),
      settingsVersion: currentVersion,
    );
  }

  /// 容错读 `{String: String}`：不是对象 → 空表；键或值不是字符串的条目丢掉。
  static Map<String, String> _stringMap(Object? raw) {
    final out = <String, String>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      if (key is String && value is String) out[key] = value;
    });
    return out;
  }

  @override
  String toString() => 'AppSettings($currentTimetableId, $themeId)';
}
