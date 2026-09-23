import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';

/// v1.3.0 Phase C 测试共用的小工具。
///
/// `testWidgets` 跑在 fake async 区里，而 `Storage` 写的是真实文件，
/// 所以任何会 `_commit()` 的操作之后都要 [settleWithRealIo]：
/// 让出真实时间 + flush 一次 fake async 的微任务队列，重复几次。
Future<void> settleWithRealIo(WidgetTester tester, {int rounds = 20}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// 每个测试一个临时存储目录。
class TempStorage {
  late Directory dir;

  Future<void> setUp(String name) async {
    dir = await Directory.systemTemp.createTemp(name);
    Storage.overrideDirectory = dir;
  }

  Future<void> tearDown() async {
    Storage.overrideDirectory = null;
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows 上偶尔还有未关闭的句柄，留给系统清理临时目录。
    }
  }
}

/// 在真实 IO 里建好 AppState + ThemeController（主题要读 asset）。
Future<(AppState, ThemeController)> loadState(
  WidgetTester tester, {
  Future<void> Function(AppState state)? seed,
}) async {
  late AppState state;
  late ThemeController controller;
  await tester.runAsync(() async {
    state = AppState();
    await state.load();
    if (seed != null) await seed(state);
    controller = ThemeController(state);
    await controller.load();
  });
  return (state, controller);
}

/// 把 [home] 包进 Provider + MaterialApp。
Future<void> pumpApp(
  WidgetTester tester,
  AppState state,
  ThemeController controller,
  Widget home, {
  Size size = const Size(900, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<ThemeController>.value(value: controller),
      ],
      child: MaterialApp(theme: controller.current.toThemeData(), home: home),
    ),
  );
  await tester.pump();
}
