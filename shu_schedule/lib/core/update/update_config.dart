/// 检查更新的配置：更新源、超时、频率。
///
/// 发布前把 [sources] 里的 `OWNER/REPO` 换成真实的 GitHub 仓库即可启用；
/// 只要还有占位符，[isConfigured] 就是 false，App 不会发出任何更新请求，
/// 设置页的「检查更新」显示「未配置更新源」并禁用。
///
/// `latest.json` 的格式：
/// ```json
/// {
///   "versionCode": 8,
///   "versionName": "1.3.1",
///   "changelog": "修复了……\n新增了……",
///   "downloadUrls": ["https://github.com/OWNER/REPO/releases/download/v1.3.1/jiankebiao-v1.3.1-arm64.apk"],
///   "sha256": "0123abcd…"
/// }
/// ```
/// `versionCode` 和 Android 的 versionCode（pubspec `version` 里 `+` 后面那个数）比。
class UpdateConfig {
  UpdateConfig._();

  /// 依次尝试的更新源：GitHub raw 在前，jsDelivr 镜像在后（国内网络下 raw 常常连不上）。
  static const List<String> sources = <String>[
    'https://raw.githubusercontent.com/OWNER/REPO/main/latest.json',
    'https://cdn.jsdelivr.net/gh/OWNER/REPO@main/latest.json',
  ];

  /// 占位符。
  static const String placeholder = 'OWNER/REPO';

  /// 每个源的超时（连接 + 读完整个响应）。
  static const Duration perSourceTimeout = Duration(seconds: 5);

  /// `latest.json` 最大字节数，超过就当这个源坏了（防止被塞一个大文件）。
  static const int maxResponseBytes = 64 * 1024;

  /// 更新源是否都已经配置好（没有占位符、至少一个）。
  static bool get isConfigured => sourcesConfigured(sources);

  /// [isConfigured] 的纯函数版本，测试用。
  static bool sourcesConfigured(List<String> list) =>
      list.isNotEmpty && list.every((s) => !s.contains(placeholder));
}
