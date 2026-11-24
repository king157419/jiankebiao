import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import 'course_editor_page.dart';

/// 导入流程的路由名，在 `main.dart` 里注册（`ImportFlowPage`）。
///
/// v1.4.0 从 `week_view_page.dart` 挪到这里（那边 `export` 了它，
/// 原来的 `import 'week_view_page.dart' show importRouteName` 照样能用）。
const String importRouteName = '/import';

/// 「还没有课」的空状态：两个入口（周视图用）。
///
/// 1. 从教务导入（`<prefix>-primary`）→ [importRouteName]；
/// 2. 手动添加（`<prefix>-secondary`）→ 课程编辑页，预选 [initialDay] 第 1 节。
///
/// v1.5.0 删掉了第三个入口「打开同学分享的文件」。
class TimetableEmptyState extends StatelessWidget {
  final AppTheme theme;

  /// 按钮 key 前缀，例如 `week-empty`。
  final String keyPrefix;
  final String title;
  final String? message;
  final String emoji;

  /// 「手动添加」预选的星期（1..7）。
  final int initialDay;

  /// 测试用时钟（一张课表都没有时「手动添加」弹周次面板的「今天」）；不传用 [DateTime.now]。
  final DateTime Function()? clock;

  const TimetableEmptyState({
    super.key,
    required this.theme,
    required this.keyPrefix,
    required this.title,
    this.message,
    this.emoji = '🌱',
    this.initialDay = 1,
    this.clock,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      theme: theme,
      emoji: emoji,
      title: title,
      message: message,
      keyPrefix: keyPrefix,
      primaryLabel: '从教务导入',
      onPrimary: () => Navigator.of(context).pushNamed(importRouteName),
      secondaryLabel: '手动添加',
      onSecondary: () => Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => CourseEditorPage(
            initialDay: initialDay,
            initialStartPeriod: 1,
            clock: clock,
          ),
        ),
      ),
    );
  }
}
