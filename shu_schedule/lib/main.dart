import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'features/import/adapters/school_registry.dart';
import 'features/import/pages/import_flow_page.dart';
import 'features/timetable/week_view_page.dart' show importRouteName;

/// 应用入口。
///
/// `ShuScheduleApp` 自己创建并 `load()` `AppState` / `ThemeController`，
/// 这里只负责把 B2 的导入流程注册到 `/import` 路由上
/// （周视图右上角菜单和空状态引导都 `pushNamed(importRouteName)`）。
///
/// 桌面小组件的推送（`WidgetSync.push`）挂在 `ShuScheduleApp` 内部，
/// 启动后推一次，之后每次数据/主题变更防抖 800ms 再推。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ShuScheduleApp(
      extraRoutes: <String, WidgetBuilder>{
        importRouteName: (_) => const ImportFlowPage(),
      },
    ),
  );
  // 学校清单（assets/schools.json）后台预读：课程详情里要用它显示「来自哪所学校导入」。
  // 读不到也没关系，导入页进去时还会再 ensureLoaded 一次。
  unawaited(SchoolRegistry.ensureLoaded());
}
