import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 通用空状态：表情 + 标题 + 说明 + 最多两个入口。
///
/// 插画只是装饰，含义由文字完整表达（DESIGN.md §6）。
/// 给了 [keyPrefix] 时两个按钮分别带 key `<prefix>-primary` / `-secondary`
/// （测试和截图脚本用）。
class EmptyState extends StatelessWidget {
  final AppTheme theme;
  final String emoji;
  final String title;
  final String? message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// 按钮 key 的前缀；null 时按钮不带 key。
  final String? keyPrefix;

  const EmptyState({
    super.key,
    required this.theme,
    required this.emoji,
    required this.title,
    this.message,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.keyPrefix,
  });

  Key? _buttonKey(String slot) =>
      keyPrefix == null ? null : ValueKey<String>('$keyPrefix-$slot');

  @override
  Widget build(BuildContext context) {
    final colors = theme.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ExcludeSemantics(
              child: Text(emoji, style: const TextStyle(fontSize: 56)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
                fontFamily: theme.titleFontFamily,
              ),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.onSurfaceMuted),
              ),
            ],
            if (primaryLabel != null) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton(
                key: _buttonKey('primary'),
                onPressed: onPrimary,
                child: Text(primaryLabel!),
              ),
            ],
            if (secondaryLabel != null) ...<Widget>[
              const SizedBox(height: 8),
              TextButton(
                key: _buttonKey('secondary'),
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
