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

  /// 用户同意过的隐私说明版本（`PrivacyPolicy.version`）。0 = 从没同意过：
  /// 首次启动（以及从 1.2.0 覆盖安装上来）会弹一次「隐私说明」，同意之前 App
  /// 不做任何联网请求。v1.3.0 新增，旧存档没有这个字段 → 0（不需要升 [settingsVersion]）。
  int privacyAcceptedVersion;

  /// 上一次检查更新的时间（本地时间）；null = 从没查过。
  /// 用来保证「每天最多自动查一次」。v1.3.0 新增，旧存档 → null。
  DateTime? lastUpdateCheck;

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
    this.privacyAcceptedVersion = 0,
    this.lastUpdateCheck,
    this.settingsVersion = currentVersion,
  });

  /// 出厂默认设置。
  factory AppSettings.defaults() => AppSettings();

  AppSettings copyWith({
    String? currentTimetableId,
    String? themeId,
    bool? showNonCurrentWeekCourses,
    bool? showTimeInGrid,
    bool? rememberEduLogin,
    int? privacyAcceptedVersion,
    DateTime? lastUpdateCheck,
    int? settingsVersion,
  }) => AppSettings(
    currentTimetableId: currentTimetableId ?? this.currentTimetableId,
    themeId: themeId ?? this.themeId,
    showNonCurrentWeekCourses:
        showNonCurrentWeekCourses ?? this.showNonCurrentWeekCourses,
    showTimeInGrid: showTimeInGrid ?? this.showTimeInGrid,
    rememberEduLogin: rememberEduLogin ?? this.rememberEduLogin,
    privacyAcceptedVersion:
        privacyAcceptedVersion ?? this.privacyAcceptedVersion,
    lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
    settingsVersion: settingsVersion ?? this.settingsVersion,
  );

  Map<String, dynamic> toJson() => {
    'currentTimetableId': currentTimetableId,
    'themeId': themeId,
    'showNonCurrentWeekCourses': showNonCurrentWeekCourses,
    'showTimeInGrid': showTimeInGrid,
    'rememberEduLogin': rememberEduLogin,
    'privacyAcceptedVersion': privacyAcceptedVersion,
    'lastUpdateCheck': lastUpdateCheck?.toIso8601String(),
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
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final version = versionOf(json);
    var showTimeInGrid = json['showTimeInGrid'] is bool
        ? json['showTimeInGrid'] as bool
        : false;
    // v1 → v2：不管 v1 里写的是什么，都按新默认值（false）走一次，只迁移这一次。
    if (version < 2) showTimeInGrid = false;
    final privacy = json['privacyAcceptedVersion'];
    final lastCheck = json['lastUpdateCheck'];
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
      privacyAcceptedVersion: privacy is num && privacy > 0
          ? privacy.toInt()
          : 0,
      lastUpdateCheck: lastCheck is String
          ? DateTime.tryParse(lastCheck)
          : null,
      settingsVersion: currentVersion,
    );
  }

  @override
  String toString() => 'AppSettings($currentTimetableId, $themeId)';
}
