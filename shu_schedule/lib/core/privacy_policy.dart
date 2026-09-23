/// 隐私说明的版本与位置。
///
/// 正文在 `assets/privacy.md`（设置 → 隐私说明）。**改了正文里的实质内容**
/// （多收集了什么、多了一种联网请求、多了权限）就把 [version] 加 1：
/// 已经同意过旧版本的用户下次启动会再看到一次确认弹窗
/// （`AppSettings.privacyAcceptedVersion < version`）。只改错别字不用加。
class PrivacyPolicy {
  PrivacyPolicy._();

  /// 当前隐私说明版本（从 1 开始；0 表示从没同意过）。
  static const int version = 1;

  /// 正文更新日期（和 privacy.md 末尾保持一致）。
  static const String updatedAt = '2026-09-23';

  /// 正文 asset 路径。
  static const String assetPath = 'assets/privacy.md';
}
