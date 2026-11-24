/// 「上课提醒」的用户偏好（v1.4.0）。存在 [AppSettings.reminders] 里，
/// 跟着 settings.json 和备份走（它是用户偏好，不是这台手机的状态）；
/// 通知 / 精确闹钟的权限状态不存，每次从系统现查。
///
/// 不可变：改动用 [copyWith] 生成新对象，再交给 `AppState.setReminderSettings`。
class ReminderSettings {
  /// 设置页里可选的「提前多少分钟」。
  static const List<int> leadChoices = <int>[5, 10, 15, 20, 30];

  /// 默认提前 15 分钟。
  static const int defaultLeadMinutes = 15;

  /// 总开关。出厂关闭：开启时才申请通知权限。
  final bool enabled;

  /// 上课前多少分钟提醒，取值见 [leadChoices]。
  final int leadMinutes;

  /// 前一天晚上的「明日预告」。
  final bool eveningPreview;

  /// 明日预告的时刻（本地时间）。
  final int previewHour;
  final int previewMinute;

  const ReminderSettings({
    this.enabled = false,
    this.leadMinutes = defaultLeadMinutes,
    this.eveningPreview = true,
    this.previewHour = 21,
    this.previewMinute = 0,
  });

  ReminderSettings copyWith({
    bool? enabled,
    int? leadMinutes,
    bool? eveningPreview,
    int? previewHour,
    int? previewMinute,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    leadMinutes: leadMinutes ?? this.leadMinutes,
    eveningPreview: eveningPreview ?? this.eveningPreview,
    previewHour: previewHour ?? this.previewHour,
    previewMinute: previewMinute ?? this.previewMinute,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'leadMinutes': leadMinutes,
    'eveningPreview': eveningPreview,
    'previewHour': previewHour,
    'previewMinute': previewMinute,
  };

  /// 容错解析：不是 Map → 默认值；单个字段类型不对 / 越界 → 该字段默认值。
  /// 提前分钟数不在 [leadChoices] 里也回到默认（界面只能选这几个）。
  factory ReminderSettings.fromJson(Object? json) {
    if (json is! Map) return const ReminderSettings();
    const d = ReminderSettings();
    final lead = _asInt(json['leadMinutes']);
    final hour = _asInt(json['previewHour']);
    final minute = _asInt(json['previewMinute']);
    return ReminderSettings(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : d.enabled,
      leadMinutes: lead != null && leadChoices.contains(lead)
          ? lead
          : d.leadMinutes,
      eveningPreview: json['eveningPreview'] is bool
          ? json['eveningPreview'] as bool
          : d.eveningPreview,
      previewHour: hour != null && hour >= 0 && hour <= 23
          ? hour
          : d.previewHour,
      previewMinute: minute != null && minute >= 0 && minute <= 59
          ? minute
          : d.previewMinute,
    );
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num && v == v.roundToDouble()) return v.toInt();
    return null;
  }

  /// 「21:00」这样的预告时刻文字。
  String get previewTimeText =>
      '${previewHour.toString().padLeft(2, '0')}:'
      '${previewMinute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.leadMinutes == leadMinutes &&
      other.eveningPreview == eveningPreview &&
      other.previewHour == previewHour &&
      other.previewMinute == previewMinute;

  @override
  int get hashCode => Object.hash(
    enabled,
    leadMinutes,
    eveningPreview,
    previewHour,
    previewMinute,
  );

  @override
  String toString() =>
      'ReminderSettings(enabled: $enabled, lead: $leadMinutes, '
      'preview: $eveningPreview $previewTimeText)';
}
