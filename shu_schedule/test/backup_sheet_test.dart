import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/features/settings/backup_service.dart';
import 'package:shu_schedule/features/settings/backup_sheet.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';
import 'package:shu_schedule/features/settings/system_share.dart';
import 'package:shu_schedule/models/app_settings.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/harness.dart';
import 'helpers/reminder_fixtures.dart';

/// v1.5.0 D6：设置 →「备份与恢复」面板 → 导出备份文件 / 从备份文件恢复（合并 / 覆盖）。
///
/// 文件选择和系统分享通过 [BackupService.pickText] / [BackupService.shareFile]
/// 两个钩子注入，不碰插件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = TempStorage();
  setUp(() => storage.setUp('backup_sheet'));
  tearDown(() async {
    BackupService.resetIo();
    await storage.tearDown();
  });

  ValueKey<String> k(String s) => ValueKey<String>(s);

  Future<(AppState, ThemeController)> seeded(WidgetTester tester) =>
      loadState(tester, seed: (s) => s.addTimetable(buildTimetable()));

  Future<void> pumpSettings(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
  ) => pumpApp(
    tester,
    state,
    controller,
    SettingsPage(updateChecker: UpdateChecker(sources: const <String>[])),
    size: const Size(900, 4000),
  );

  /// 设置页 →「备份与恢复」→ 面板里的 [action]。
  Future<void> choose(WidgetTester tester, String action) async {
    await tester.tap(find.byKey(k('settings-backup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(k(action)));
    await tester.pump();
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(k(key)));
    await tester.pump();
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
  }

  /// 1.3 / 1.4 「分享此课表」导出的单表文件（`kind: timetable`，没有 settings）。
  String legacySharedFile(Timetable tt) =>
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'version': 2,
        'kind': 'timetable',
        'app': '简课表',
        'exportedAt': '2026-09-23T10:00:00.000',
        'timetables': <dynamic>[tt.toJson()],
      });

  group('导出', () {
    test('requestFor：文件名带时间戳，内容能被 Storage.importJson 读回', () async {
      final state = AppState();
      await state.load();
      await state.addTimetable(buildTimetable());
      final req = BackupService.requestFor(
        state,
        now: DateTime(2026, 10, 8, 9, 30, 5),
      );
      expect(req.fileName, 'jiankebiao-backup-2026-10-08T09-30-05.json');
      expect(req.mimeType, 'application/json');
      final back = Storage.importJson(req.content);
      expect(back.timetables.single.name, '测试课表');
      expect(back.timetables.single.courses.length, 3);
    });

    testWidgets('面板 →「导出备份文件」：交给系统分享，面板关掉', (tester) async {
      final (state, controller) = await seeded(tester);
      final shared = <ShareFileRequest>[];
      BackupService.shareFile = (r) async {
        shared.add(r);
        return true;
      };
      await pumpSettings(tester, state, controller);

      await choose(tester, 'backup-export');

      expect(shared, hasLength(1));
      expect(
        shared.single.fileName,
        matches(
          RegExp(r'^jiankebiao-backup-\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d\.json$'),
        ),
      );
      final back = Storage.importJson(shared.single.content);
      expect(back.timetables.map((t) => t.name), <String>['测试课表']);
      expect(back.settings.currentTimetableId, 't');
      expect(find.byKey(k('backup-sheet')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('openBackupAndRestore 的 clock 决定文件名', (tester) async {
      final (state, controller) = await seeded(tester);
      final shared = <ShareFileRequest>[];
      BackupService.shareFile = (r) async {
        shared.add(r);
        return true;
      };
      await pumpApp(
        tester,
        state,
        controller,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openBackupAndRestore(
                context,
                state,
                clock: () => DateTime(2026, 10, 8, 21, 5),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, 'backup-export');
      expect(
        shared.single.fileName,
        'jiankebiao-backup-2026-10-08T21-05-00.json',
      );
    });

    testWidgets('分享出错 → 白话提示，不把异常原样给用户看', (tester) async {
      final (state, controller) = await seeded(tester);
      BackupService.shareFile = (_) async =>
          throw Exception('PlatformException(share_failed)');
      await pumpSettings(tester, state, controller);

      await choose(tester, 'backup-export');

      expect(find.text('没能导出备份，请再试一次'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });

  group('恢复', () {
    testWidgets('合并：id 冲突的那张换新 id、名字加「（导入）」，现有课表不动', (tester) async {
      final (state, controller) = await seeded(tester);
      // 用本机自己的导出当备份：id 一定冲突。
      final text = Storage.exportJson(state.timetables, state.settings);
      BackupService.pickText = () async => text;
      await pumpSettings(tester, state, controller);

      await choose(tester, 'backup-restore');
      final dialog = find.byKey(k('backup-restore-dialog'));
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('从备份恢复')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('备份里有 1 张课表'),
        ),
        findsOneWidget,
      );

      // R1-14：按钮顺序「取消 / 覆盖 / 合并」，「合并」为 FilledButton 主按钮，「覆盖」用 error 色。
      final cancelBtn = find.descendant(of: dialog, matching: find.text('取消'));
      final replaceBtn = find.byKey(k('backup-restore-replace'));
      final mergeBtn = find.byKey(k('backup-restore-merge'));
      expect(
        tester.getTopLeft(cancelBtn).dx,
        lessThan(tester.getTopLeft(replaceBtn).dx),
      );
      expect(
        tester.getTopLeft(replaceBtn).dx,
        lessThan(tester.getTopLeft(mergeBtn).dx),
      );
      expect(tester.widget(mergeBtn), isA<FilledButton>());
      final replaceWidget = tester.widget<TextButton>(replaceBtn);
      final dialogTheme = Theme.of(tester.element(dialog));
      expect(
        replaceWidget.style?.foregroundColor?.resolve(const <WidgetState>{}),
        dialogTheme.colorScheme.error,
      );

      await tapAndSettle(tester, 'backup-restore-merge');

      expect(state.timetables, hasLength(2));
      expect(state.timetables.first.id, 't');
      expect(state.timetables.first.name, '测试课表');
      final added = state.timetables.last;
      expect(added.id, isNot('t'));
      expect(added.name, '测试课表（导入）');
      expect(added.courses.length, 3);
      expect(state.currentTimetable!.id, 't', reason: '合并不切换当前课表');
      expect(find.text('已合并 1 张课表'), findsOneWidget);
    });

    testWidgets('覆盖：整体换成备份里的课表', (tester) async {
      final (state, controller) = await seeded(tester);
      final text = Storage.exportJson(<Timetable>[
        Timetable.empty(id: 'b', name: '备份里的课表'),
      ], AppSettings(currentTimetableId: 'b'));
      BackupService.pickText = () async => text;
      await tester.runAsync(Storage.flushPendingWrites);
      await pumpSettings(tester, state, controller);

      await choose(tester, 'backup-restore');
      await tapAndSettle(tester, 'backup-restore-replace');

      expect(state.timetables.map((t) => t.name), <String>['备份里的课表']);
      expect(state.currentTimetable!.id, 'b');
      expect(find.text('已用备份覆盖全部数据'), findsOneWidget);
      // v1.5.0 任务 E：覆盖前照样留一份旧数据，但设置页顶部不再出红卡
      // 「读取数据时发现问题 / 恢复前的旧数据已备份到 <本机路径>」。
      expect(
        storage.dir.listSync().where(
          (e) => e.path.contains('.before-restore-'),
        ),
        hasLength(1),
      );
      expect(state.warnings, isEmpty);
      expect(find.text('读取数据时发现问题'), findsNothing);
      expect(find.textContaining('已备份到'), findsNothing);
    });

    testWidgets('对话框点「取消」：什么都不变', (tester) async {
      final (state, controller) = await seeded(tester);
      final text = Storage.exportJson(<Timetable>[
        Timetable.empty(id: 'b', name: '备份里的课表'),
      ], AppSettings(currentTimetableId: 'b'));
      BackupService.pickText = () async => text;
      await pumpSettings(tester, state, controller);

      await choose(tester, 'backup-restore');
      await tapAndSettle(tester, 'backup-restore-cancel');

      expect(find.byKey(k('backup-restore-dialog')), findsNothing);
      expect(state.timetables.map((t) => t.id), <String>['t']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('选文件时取消：不弹对话框，什么都不变', (tester) async {
      final (state, controller) = await seeded(tester);
      var picks = 0;
      BackupService.pickText = () async {
        picks++;
        return null;
      };
      await pumpSettings(tester, state, controller);

      await choose(tester, 'backup-restore');

      expect(picks, 1);
      expect(find.byKey(k('backup-restore-dialog')), findsNothing);
      expect(state.timetables.map((t) => t.id), <String>['t']);
      expect(find.byType(SnackBar), findsNothing);
    });

    for (final (label, content) in <(String, String)>[
      ('不是 JSON', 'not a backup'),
      ('JSON 但不是备份', '{"hello":1}'),
      ('顶层是数组', '[]'),
    ]) {
      testWidgets('坏文件（$label）→「这不是简课表的备份文件」，不提 JSON / 解析错误', (tester) async {
        final (state, controller) = await seeded(tester);
        BackupService.pickText = () async => content;
        await pumpSettings(tester, state, controller);

        await choose(tester, 'backup-restore');

        expect(find.text('这不是简课表的备份文件'), findsOneWidget);
        expect(backupNotBackupText, '这不是简课表的备份文件');
        expect(find.textContaining('JSON'), findsNothing);
        expect(find.textContaining('timetables'), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
        expect(find.byKey(k('backup-restore-dialog')), findsNothing);
        expect(state.timetables.map((t) => t.id), <String>['t']);
      });
    }

    testWidgets('读文件出错 →「没能读取这个文件」', (tester) async {
      final (state, controller) = await seeded(tester);
      BackupService.pickText = () async =>
          throw const FileSystemExceptionLike('Permission denied');
      await pumpSettings(tester, state, controller);

      await choose(tester, 'backup-restore');

      expect(find.text('没能读取这个文件'), findsOneWidget);
      expect(find.textContaining('Permission'), findsNothing);
    });

    testWidgets('向后兼容：1.3 / 1.4「分享此课表」的单表文件可以合并进来', (tester) async {
      final (state, controller) = await seeded(tester);
      final friend = buildTimetable().copyWith(id: 'friend', name: '同学的课表');
      BackupService.pickText = () async => legacySharedFile(friend);
      await pumpSettings(tester, state, controller);

      await choose(tester, 'backup-restore');
      expect(find.textContaining('备份里有 1 张课表'), findsOneWidget);
      await tapAndSettle(tester, 'backup-restore-merge');

      expect(state.timetables.map((t) => t.name), <String>['测试课表', '同学的课表']);
      expect(state.timetables.last.id, 'friend', reason: 'id 不冲突就保留');
      expect(state.timetables.last.courses.length, 3);
      expect(state.currentTimetable!.id, 't');
      expect(find.text('已合并 1 张课表'), findsOneWidget);
    });
  });
}

/// 模拟读文件时的 IO 错误（不是 [FormatException]）。
class FileSystemExceptionLike implements Exception {
  final String message;
  const FileSystemExceptionLike(this.message);

  @override
  String toString() => 'FileSystemException: $message';
}
