import '../repo_config.dart';

/// 检查更新的配置：更新源、超时、频率。
///
/// 更新源从 `lib/core/repo_config.dart` 的 `kRepo` 派生（v1.4.0 起），发布前只改那一个文件；
/// 只要 `kRepo` 还是占位符，[isConfigured] 就是 false，App 不会发出任何更新请求，
/// 设置页的「检查更新」显示「未配置更新源」并禁用。
///
/// `latest.json`（放在仓库根目录，`tool/gen_latest.py` 生成）的格式：
/// ```json
/// {
///   "versionCode": 9,
///   "versionName": "1.4.0",
///   "changelog": "修复了……\n新增了……",
///   "downloadUrls": ["https://github.com/<owner>/<repo>/releases/download/v1.4.0/jiankebiao-v1.4.0-arm64.apk"],
///   "sha256": "0123abcd…",
///   "holidays": {"sha256": "…", "updatedAt": "2026-10-06"}
/// }
/// ```
/// `versionCode` 和 Android 的 versionCode（pubspec `version` 里 `+` 后面那个数）比。
/// `holidays` 可选：有就用它校验远程假日表（`HolidayRepository`）的 SHA-256。
class UpdateConfig {
  UpdateConfig._();

  /// 依次尝试的更新源：Gitee raw（若配置）→ jsDelivr → raw.githubusercontent.com
  /// （国内网络下 raw.githubusercontent.com 常常连不上，放最后）。
  static List<String> get sources => <String>[
    for (final uri in kRepo.rawUrls(latestJsonPath)) uri.toString(),
  ];

  /// `latest.json` 在仓库里的路径。
  static const String latestJsonPath = 'latest.json';

  /// 仓库占位符（[RepoConfig.placeholderSlug]，定义在 `repo_config.dart`）。
  static const String placeholder = RepoConfig.placeholderSlug;

  /// 每个源的超时（连接 + 读完整个响应）。
  static const Duration perSourceTimeout = Duration(seconds: 5);

  /// `latest.json` 最大字节数，超过就当这个源坏了（防止被塞一个大文件）。
  static const int maxResponseBytes = 64 * 1024;

  /// 更新源是否已经配置好（`kRepo` 不是占位符）。
  static bool get isConfigured =>
      kRepo.isConfigured && sourcesConfigured(sources);

  /// 一组自定义源是否可用（没有占位符、至少一个），测试和注入的 checker 用。
  static bool sourcesConfigured(List<String> list) =>
      list.isNotEmpty && list.every((s) => !s.contains(placeholder));
}
