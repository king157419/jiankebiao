import 'package:flutter/material.dart';

import 'school_select_page.dart';

/// 「从教务系统导入课表」整条流程的入口页。
///
/// 流程：选择学校 → WebView 登录 → 一键导入（注入 JS） → 预览确认 → 回首页。
///
/// 接线方式（Phase 3）：
/// ```dart
/// MaterialApp(
///   routes: {ImportFlowPage.routeName: (_) => const ImportFlowPage()},
/// );
/// Navigator.of(context).pushNamed(ImportFlowPage.routeName);
/// ```
/// 前提：上层已经有 `ChangeNotifierProvider<AppState>`，预览页确认时会
/// 通过 `context.read<AppState>()` 写入课表。
class ImportFlowPage extends StatelessWidget {
  const ImportFlowPage({super.key});

  /// 建议的命名路由。
  static const String routeName = '/import';

  @override
  Widget build(BuildContext context) => const SchoolSelectPage();
}
