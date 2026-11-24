/// 发布仓库的唯一配置点（v1.4.0）。
///
/// 「检查更新」的 `latest.json`、远程假日表 `holidays.json`、「反馈」的 GitHub Issues
/// 地址都从 [kRepo] 派生。**发布前只需要改这一个文件**：把 [kRepo] 里的
/// `OWNER` / `REPO` 换成真实的 GitHub 仓库；如果在 Gitee 上有同步镜像，再填上
/// `giteeOwner` / `giteeRepo`（国内网络优先走 Gitee）。
///
/// 只要还是占位符（[RepoConfig.isPlaceholder]），App 就不会发出任何更新 / 假日表请求，
/// 设置页的「检查更新」显示「未配置更新源」并禁用，反馈页不给 GitHub 链接。
class RepoConfig {
  const RepoConfig({
    required this.githubOwner,
    required this.githubRepo,
    this.giteeOwner = '',
    this.giteeRepo = '',
    this.branch = 'main',
  });

  /// 占位符：没换成真实仓库之前 [kRepo] 用的就是它们。
  static const String placeholderOwner = 'OWNER';
  static const String placeholderRepo = 'REPO';

  /// `OWNER/REPO`：URL 里出现它就说明还没配置（`UpdateConfig.sourcesConfigured` 用）。
  static const String placeholderSlug = '$placeholderOwner/$placeholderRepo';

  final String githubOwner;
  final String githubRepo;

  /// Gitee 镜像（可选，空串 = 没有）。
  final String giteeOwner;
  final String giteeRepo;

  /// 读取 raw 文件用的分支。
  final String branch;

  /// 还是占位符（或者没填）。
  bool get isPlaceholder =>
      githubOwner == placeholderOwner ||
      githubRepo == placeholderRepo ||
      githubOwner.trim().isEmpty ||
      githubRepo.trim().isEmpty;

  /// 已经配置成真实仓库。
  bool get isConfigured => !isPlaceholder;

  /// 配置了 Gitee 镜像。
  bool get hasGitee =>
      giteeOwner.trim().isNotEmpty && giteeRepo.trim().isNotEmpty;

  /// GitHub Issues 页面。
  String get issuesUrl => 'https://github.com/$githubOwner/$githubRepo/issues';

  /// 仓库里同一个文件的多个 raw 地址，按「国内可达性」排序：
  /// Gitee raw（若配置）→ jsDelivr → raw.githubusercontent.com。
  ///
  /// [path] 是相对仓库根目录的路径（如 `latest.json`、
  /// `shu_schedule/assets/holidays.json`），开头的 `/` 会被去掉。
  /// 这是纯函数：占位符状态下也照样拼地址，是否发请求由 [isConfigured] 决定。
  List<Uri> rawUrls(String path) {
    final clean = path.replaceFirst(RegExp(r'^/+'), '');
    return <Uri>[
      if (hasGitee)
        Uri.parse(
          'https://gitee.com/${giteeOwner.trim()}/${giteeRepo.trim()}'
          '/raw/$branch/$clean',
        ),
      Uri.parse(
        'https://cdn.jsdelivr.net/gh/$githubOwner/$githubRepo@$branch/$clean',
      ),
      Uri.parse(
        'https://raw.githubusercontent.com/$githubOwner/$githubRepo/$branch/$clean',
      ),
    ];
  }

  @override
  String toString() =>
      'RepoConfig($githubOwner/$githubRepo@$branch'
      '${hasGitee ? ', gitee: $giteeOwner/$giteeRepo' : ''})';
}

/// **发布前替换清单：只改这里。**
///
/// 例：`RepoConfig(githubOwner: 'someone', githubRepo: 'jiankebiao',
/// giteeOwner: 'someone', giteeRepo: 'jiankebiao')`。
const RepoConfig kRepo = RepoConfig(githubOwner: 'OWNER', githubRepo: 'REPO');
