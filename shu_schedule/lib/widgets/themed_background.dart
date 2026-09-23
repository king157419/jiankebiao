import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 按主题铺底：有 `decor.backgroundAsset` 时把插画 cover 铺满，
/// 否则用纯色 `colors.background`。
///
/// 插画只负责页面背景；文字密集区域（课表网格、列表）必须自己用
/// `colors.surface` 做底板（DESIGN.md §3）。图片加载失败时自动退回纯色。
class ThemedBackground extends StatelessWidget {
  final AppTheme theme;
  final Widget child;

  const ThemedBackground({super.key, required this.theme, required this.child});

  @override
  Widget build(BuildContext context) {
    final asset = theme.backgroundAssetPath;
    if (asset == null) {
      return Container(color: theme.colors.background, child: child);
    }
    return Container(
      color: theme.colors.background,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: ExcludeSemantics(
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
