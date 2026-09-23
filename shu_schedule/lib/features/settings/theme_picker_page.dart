import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';

/// 主题选择：卡片网格（预览色块 + 名称 + 描述），点选即时生效。
class ThemePickerPage extends StatelessWidget {
  const ThemePickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final current = controller.current;
    return Scaffold(
      appBar: AppBar(title: const Text('主题')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 172,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: controller.themes.length,
        itemBuilder: (_, i) {
          final theme = controller.themes[i];
          return _ThemeCard(
            theme: theme,
            active: current,
            selected: theme.id == current.id,
            onTap: () => controller.select(theme.id),
          );
        },
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppTheme theme;
  final AppTheme active;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.theme,
    required this.active,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${theme.name}主题',
      selected: selected,
      button: true,
      child: Material(
        color: theme.colors.background,
        borderRadius: BorderRadius.circular(active.cornerRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(active.cornerRadius),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(active.cornerRadius),
              border: Border.all(
                color: selected ? active.colors.primary : theme.colors.gridLine,
                width: selected ? 3 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: theme.colors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        theme.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colors.onSurface,
                          fontFamily: theme.titleFontFamily,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: active.colors.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // 课程色预览：模拟课表里的几个小块。
                Row(
                  children: <Widget>[
                    for (var i = 0; i < 6; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          width: 18,
                          height: 26,
                          decoration: BoxDecoration(
                            color: theme.courseBlockColor(i),
                            borderRadius: BorderRadius.circular(
                              theme.cornerRadius / 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    theme.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: theme.colors.onSurfaceMuted,
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Text(
                      theme.decor.emoji,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      theme.isDark ? '深色' : '浅色',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
