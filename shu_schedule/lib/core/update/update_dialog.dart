import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import 'update_checker.dart';

/// 打开外部链接（测试替换）。返回是否成功拉起。
typedef ExternalLauncher = Future<bool> Function(Uri uri);

/// 默认实现：交给系统浏览器（`LaunchMode.externalApplication`）。
Future<bool> launchExternally(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// 「发现新版本」对话框：版本号、更新日志、SHA-256；「去下载」跳系统浏览器，「稍后」关掉。
///
/// 不在 App 内下载 / 安装（那需要 `REQUEST_INSTALL_PACKAGES` 权限，见 REVIEW-2 §6.4）。
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  ExternalLauncher launcher = launchExternally,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final muted = Theme.of(dialogContext).colorScheme.onSurfaceVariant;
      return AlertDialog(
        title: Text('发现新版本 v${info.versionName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(info.changelog.isEmpty ? '（这个版本没有写更新日志）' : info.changelog),
              if (info.sha256 != null) ...<Widget>[
                const SizedBox(height: 12),
                SelectableText(
                  'SHA-256：${info.sha256}',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '点「去下载」会用系统浏览器打开下载页，下载后直接安装覆盖即可，课表不会丢。',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: info.downloadUrls.isEmpty
                ? null
                : () async {
                    Navigator.of(dialogContext).pop();
                    final ok = await openFirstDownload(info, launcher);
                    if (!ok) {
                      messenger?.showSnackBar(
                        const SnackBar(content: Text('没能打开浏览器，请稍后再试')),
                      );
                    }
                  },
            child: const Text('去下载'),
          ),
        ],
      );
    },
  );
}

/// 依次尝试 [UpdateInfo.downloadUrls]，第一个能拉起浏览器的为准。
Future<bool> openFirstDownload(
  UpdateInfo info,
  ExternalLauncher launcher,
) async {
  for (final url in info.downloadUrls) {
    final uri = Uri.tryParse(url);
    if (uri == null) continue;
    if (await launcher(uri)) return true;
  }
  return false;
}

/// 启动后的自动检查：满足 [UpdateChecker.shouldAutoCheck] 才查（已同意隐私说明、
/// 源已配置、今天还没查过），先记下检查时间再发请求（失败也算查过，不会一天里反复重试）。
/// 有新版才弹框；已是最新 / 失败都静默。返回这次是否真的发了请求。
Future<bool> runAutoUpdateCheck(
  BuildContext context,
  AppState appState,
  UpdateChecker checker, {
  DateTime? now,
  ExternalLauncher launcher = launchExternally,
}) async {
  final time = now ?? DateTime.now();
  final settings = appState.settings;
  if (!UpdateChecker.shouldAutoCheck(
    privacyAccepted: settings.privacyAcceptedVersion > 0,
    configured: checker.isConfigured,
    lastCheck: settings.lastUpdateCheck,
    now: time,
  )) {
    return false;
  }
  await appState.setLastUpdateCheck(time);
  final result = await checker.check();
  if (result.hasUpdate && result.info != null && context.mounted) {
    await showUpdateDialog(context, result.info!, launcher: launcher);
  }
  return true;
}

/// 设置页「检查更新」：结果都给反馈（新版弹框、已是最新 / 失败给 SnackBar）。
Future<void> runManualUpdateCheck(
  BuildContext context,
  AppState appState,
  UpdateChecker checker, {
  ExternalLauncher launcher = launchExternally,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!checker.isConfigured) {
    messenger.showSnackBar(const SnackBar(content: Text('未配置更新源')));
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('正在检查更新…')));
  await appState.setLastUpdateCheck(DateTime.now());
  final result = await checker.check();
  messenger.hideCurrentSnackBar();
  switch (result.status) {
    case UpdateStatus.available:
      if (context.mounted && result.info != null) {
        await showUpdateDialog(context, result.info!, launcher: launcher);
      }
    case UpdateStatus.upToDate:
      messenger.showSnackBar(const SnackBar(content: Text('已是最新版本')));
    case UpdateStatus.notConfigured:
      messenger.showSnackBar(const SnackBar(content: Text('未配置更新源')));
    case UpdateStatus.failed:
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '检查更新失败：${result.errors.isEmpty ? '网络不通' : result.errors.join('；')}',
          ),
        ),
      );
  }
}
