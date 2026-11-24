/// App 品牌常量：显示名只在这里和 `android/app/src/main/res/values/strings.xml`
/// （`app_name`）两处定义，改名时两处一起改。
///
/// Android 包名 `cn.shu.schedule`、pubspec 的包名、课程 id 前缀 `zfsoft-shu`
/// 都是历史标识，用户看不到，**不要跟着改**（改包名等于发布一个新 App）。
class AppBrand {
  AppBrand._();

  /// 显示名（桌面图标、标题、关于页、分享文案）。
  static const String name = '简课表';

  /// ASCII 短名：用在备份文件名等不适合出现中文的地方。
  static const String slug = 'jiankebiao';

  /// 一句话介绍。
  static const String tagline = '无广告、不联网上传的课程表';
}

/// 应用版本号（显示用）。发版时和 `pubspec.yaml` 的 version 同步
/// （v1.3.0 起从 about_page.dart 挪到这里，about_page 仍然 re-export 它）。
/// 检查更新比较的是 package_info_plus 读到的 versionCode，不是这个字符串。
const String appVersion = '1.5.0';
