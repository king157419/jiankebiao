import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../holiday_presets.dart';
import '../holiday_repository.dart';
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

/// 「发现新版本」对话框：版本号、更新日志；「去下载」跳系统浏览器，「稍后」关掉。
/// 校验值（`UpdateInfo.sha256`）不显示：学生用不上（v1.5.0 任务 E）。
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

/// 启动后的自动检查：满足 [UpdateChecker.shouldAutoCheck] 才查（源已配置、
/// 今天还没查过），先记下检查时间再发请求（失败也算查过，不会一天里反复重试）。
/// 有新版才弹框；已是最新 / 失败都静默。返回这次是否真的发了请求。
///
/// v1.4.0：检查成功（读到了 `latest.json`）后顺带刷新一次假日表
/// （[HolidayRepository.refreshFor]，受 24 小时节流，用这份 `latest.json` 校验 SHA-256），
/// 和更新对话框并行，失败静默。[holidays] 为测试注入，null = 默认仓库。
///
/// v1.5.0：假日表这次真的更新了（[HolidayRefreshStatus.updated]）时，用新数据调用
/// [onHolidaysUpdated]（首页据此重新算校历建议，PLAN-1.5 D9 触发点 (c)）。
Future<bool> runAutoUpdateCheck(
  BuildContext context,
  AppState appState,
  UpdateChecker checker, {
  DateTime? now,
  ExternalLauncher launcher = launchExternally,
  HolidayRepository? holidays,
  void Function(HolidayPresets? previous, HolidayPresets presets)?
  onHolidaysUpdated,
}) async {
  final time = now ?? DateTime.now();
  final settings = appState.settings;
  if (!UpdateChecker.shouldAutoCheck(
    configured: checker.isConfigured,
    lastCheck: settings.lastUpdateCheck,
    now: time,
  )) {
    return false;
  }
  await appState.setLastUpdateCheck(time);
  final result = await checker.check();
  final succeeded =
      result.status == UpdateStatus.available ||
      result.status == UpdateStatus.upToDate;
  final holidayRefresh = succeeded
      ? refreshHolidaysQuietly(
          holidays ?? HolidayRepository(),
          appState,
          manifest: result.info,
          now: time,
        )
      : null;
  if (result.hasUpdate && result.info != null && context.mounted) {
    await showUpdateDialog(context, result.info!, launcher: launcher);
  }
  final refreshed = await holidayRefresh;
  final presets = refreshed?.presets;
  if (refreshed != null && refreshed.isUpdated && presets != null) {
    onHolidaysUpdated?.call(refreshed.previousPresets, presets);
  }
  return true;
}

/// 静默刷新假日表：任何异常都吞掉，返回结果（出错时为 null）。
Future<HolidayRefreshResult?> refreshHolidaysQuietly(
  HolidayRepository repository,
  AppState appState, {
  UpdateInfo? manifest,
  DateTime? now,
}) async {
  try {
    return await repository.refreshFor(appState, manifest: manifest, now: now);
  } catch (_) {
    return null;
  }
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
      debugPrint(
        '检查更新失败：${result.errors.isEmpty ? '网络不通' : result.errors.join('；')}',
      );
      messenger.showSnackBar(const SnackBar(content: Text('没能检查更新，稍后再试')));
  }
}
