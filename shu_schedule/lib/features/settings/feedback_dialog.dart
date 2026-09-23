import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/device_diagnostics.dart';
import '../../core/feedback_links.dart';
import '../../core/update/update_dialog.dart'
    show ExternalLauncher, launchExternally;

/// 设置 → 反馈。
///
/// - 反馈渠道已配置（[FeedbackLinks.isConfigured]）：「去 GitHub 反馈」用系统浏览器打开 Issues；
/// - 没配置：显示提示，不给可点的链接；
/// - 两种情况都有「复制诊断信息」（App 版本、Android 版本、机型），配置了邮箱时还有「复制邮箱」。
Future<void> showFeedbackDialog(
  BuildContext context, {
  Future<String> Function()? diagnostics,
  ExternalLauncher launcher = launchExternally,
  bool? configured,
  String? email,
}) {
  final isConfigured = configured ?? FeedbackLinks.isConfigured;
  final mail = email ?? FeedbackLinks.email;
  final collect = diagnostics ?? () => DeviceDiagnostics.collect();
  final messenger = ScaffoldMessenger.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('反馈'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isConfigured
                ? '遇到问题或有建议，欢迎到 GitHub Issues 里留言。附上诊断信息（App 版本、Android 版本、机型）能更快定位。'
                : '反馈渠道还没有配置好（这是开发中的版本）。你可以先点「复制诊断信息」，'
                      '连同问题描述和截图发给把 App 发给你的人。',
          ),
          if (mail.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            SelectableText('邮箱：$mail'),
          ],
          const SizedBox(height: 8),
          Text(
            '诊断信息不含课表、学号或姓名；导入失败时可以在导入页导出「诊断样本」。',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('feedback-copy-diagnostics'),
          onPressed: () async {
            final text = await collect();
            await Clipboard.setData(ClipboardData(text: text));
            messenger.showSnackBar(const SnackBar(content: Text('诊断信息已复制')));
          },
          child: const Text('复制诊断信息'),
        ),
        if (mail.isNotEmpty)
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: mail));
              messenger.showSnackBar(const SnackBar(content: Text('邮箱已复制')));
            },
            child: const Text('复制邮箱'),
          ),
        if (isConfigured)
          FilledButton(
            key: const ValueKey<String>('feedback-open-issues'),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final ok = await launcher(Uri.parse(FeedbackLinks.issuesUrl));
              if (!ok) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('没能打开浏览器')),
                );
              }
            },
            child: const Text('去 GitHub 反馈'),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
      ],
    ),
  );
}
