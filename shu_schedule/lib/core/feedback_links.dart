import 'repo_config.dart';

/// 反馈渠道。
///
/// v1.3.0 Phase B 放常量和文案；Phase C 在「设置 → 反馈」（feedback_dialog.dart）里用。
/// v1.4.0 起 Issues 地址从 `repo_config.dart` 的 `kRepo` 派生；`kRepo` 还是占位符时
/// [isConfigured] 为 false，界面上只显示文字提示，不给可点击的链接。
class FeedbackLinks {
  FeedbackLinks._();

  /// GitHub Issues 地址（从 [kRepo] 派生）。
  static String get issuesUrl => kRepo.issuesUrl;

  /// 反馈邮箱（占位，空串 = 未配置）。
  static const String email = '';

  /// [kRepo] 还是占位符时为 false。
  static bool get isConfigured => kRepo.isConfigured;

  /// 「我的学校不在列表」且网址认不出系统类型时给用户看的反馈提示。
  static const String unsupportedSchoolHint =
      '想让你的学校也能一键导入，可以把学校名称、教务系统网址和系统名称'
      '（登录页底部通常写着「正方」「强智」「青果」等）反馈给开发者。'
      '反馈入口在「设置 → 反馈」。';

  /// 导入失败时，引导用户导出导入记录的提示。
  static const String diagnosticHint =
      '可以点「导出导入记录」，把本机脱敏后的文件发给开发者帮助适配。'
      '文件只在你的手机上生成，App 不会自动上传；发送前你可以先打开检查。';
}
