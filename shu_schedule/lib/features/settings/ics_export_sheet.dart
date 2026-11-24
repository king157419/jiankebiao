import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_brand.dart';
import '../../core/app_state.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/timetable.dart';
import 'ics_exporter.dart';
import 'system_share.dart';

/// 「导出到日历（.ics）」的分享出口（v1.4.0）。
class IcsShare {
  IcsShare._();

  /// 分享文件（测试替换）。默认写临时文件并调起系统分享面板。
  @visibleForTesting
  static Future<void> Function(ShareFileRequest request) shareFile =
      _shareWithSystemSheet;

  /// 恢复默认的分享实现（测试 tearDown 用）。
  @visibleForTesting
  static void resetIo() => shareFile = _shareWithSystemSheet;

  /// 生成要分享的 .ics 文件（纯函数）。[utcOffset] 是设备当前的 UTC 偏移。
  static ShareFileRequest requestFor(
    Timetable timetable, {
    int? alarmMinutes,
    required DateTime now,
    Duration utcOffset = IcsExporter.shanghaiOffset,
  }) => ShareFileRequest(
    fileName: IcsExporter.fileNameFor(now),
    content: IcsExporter.build(
      timetable: timetable,
      alarmMinutes: alarmMinutes,
      now: now,
      utcOffset: utcOffset,
    ),
    mimeType: IcsExporter.mimeType,
    subject: '${timetable.name}（日历文件）',
    text:
        '「${timetable.name}」的课程日历（${AppBrand.name}导出，调休、停课已算好）。'
        'iPhone：打开后选「添加全部」；电脑：在 Outlook / Google 日历里导入。'
        '建议导入到一个单独的日历。',
  );

  static Future<void> _shareWithSystemSheet(ShareFileRequest request) async {
    await shareFileWithSystemSheet(request);
  }
}

/// 打开「导出到日历」底部弹窗（设置页「课表」分组、课表管理页菜单共用）。
///
/// 提醒默认取「上课提醒」的提前分钟数（在 无 / 10 / 15 / 30 里时），否则 15 分钟。
/// [clock] / [utcOffset]（设备当前 UTC 偏移）只给测试用。
Future<void> showIcsExportSheet(
  BuildContext context, {
  required Timetable timetable,
  DateTime Function()? clock,
  Duration Function()? utcOffset,
}) {
  final lead = context.read<AppState>().settings.reminders.leadMinutes;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _IcsExportSheet(
      timetable: timetable,
      initialAlarm: IcsExporter.defaultAlarmFor(lead),
      clock: clock ?? DateTime.now,
      utcOffset: utcOffset ?? () => DateTime.now().timeZoneOffset,
    ),
  );
}

/// 弹窗里的「重新导入」说明（review-G P2-4）：重新导入不会删掉旧事件。
const String icsReimportNote =
    '建议导入到一个单独的日历；课表或调休有变化时，先清空那个日历再重新导入，'
    '日历不会自动删除已取消的课。';

/// 手机当前不在 UTC+8 时弹窗里的提示（review-G P3-11）。
const String icsLocalTimeNote = '将按手机当前时区导出（手机不在北京时间 UTC+8）。';

class _IcsExportSheet extends StatefulWidget {
  final Timetable timetable;
  final int? initialAlarm;
  final DateTime Function() clock;
  final Duration Function() utcOffset;

  const _IcsExportSheet({
    required this.timetable,
    required this.initialAlarm,
    required this.clock,
    required this.utcOffset,
  });

  @override
  State<_IcsExportSheet> createState() => _IcsExportSheetState();
}

class _IcsExportSheetState extends State<_IcsExportSheet> {
  /// 选中的提醒分钟数；null = 无。
  int? _alarm;
  bool _busy = false;
  late final int _sessionCount;

  @override
  void initState() {
    super.initState();
    _alarm = widget.initialAlarm;
    _sessionCount = IcsExporter.sessionsOf(widget.timetable).length;
  }

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final request = IcsShare.requestFor(
        widget.timetable,
        alarmMinutes: _alarm,
        now: widget.clock(),
        utcOffset: widget.utcOffset(),
      );
      await IcsShare.shareFile(request);
      if (mounted) navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>().current;
    final tt = widget.timetable;
    final muted = TextStyle(fontSize: 12, color: theme.colors.onSurfaceMuted);
    final empty = _sessionCount == 0;
    final localTime = !IcsExporter.usesShanghaiTime(widget.utcOffset());

    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey<String>('ics-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '导出到日历（.ics）',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: theme.colors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              empty
                  ? '「${tt.name}」学期内没有课，没有可导出的内容'
                  : '「${tt.name}」· 第 1-${tt.config.totalWeeks} 周 · '
                        '共 $_sessionCount 节课，调休、停课已算好',
              key: const ValueKey<String>('ics-summary'),
              style: muted,
            ),
            const SizedBox(height: 12),
            Text(
              'iPhone：微信/AirDrop 打开后选「添加全部」；电脑：Outlook / Google 日历导入',
              key: const ValueKey<String>('ics-hint'),
              style: TextStyle(fontSize: 13, color: theme.colors.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              icsReimportNote,
              key: const ValueKey<String>('ics-reimport-note'),
              style: muted,
            ),
            if (localTime) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                icsLocalTimeNote,
                key: const ValueKey<String>('ics-local-time-note'),
                style: muted,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '课前提醒（由日历 App 提醒）',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                ChoiceChip(
                  key: const ValueKey<String>('ics-alarm-0'),
                  label: const Text('无'),
                  selected: _alarm == null,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _alarm = null),
                ),
                for (final n in IcsExporter.alarmChoices)
                  ChoiceChip(
                    key: ValueKey<String>('ics-alarm-$n'),
                    label: Text('$n 分钟'),
                    selected: _alarm == n,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _alarm = n),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey<String>('ics-share'),
              onPressed: (_busy || empty) ? null : _share,
              icon: const Icon(Icons.ios_share),
              label: Text(_busy ? '正在生成…' : '生成并分享'),
            ),
          ],
        ),
      ),
    );
  }
}
