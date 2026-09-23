import 'package:flutter/material.dart';

import '../../core/app_brand.dart';
import '../../core/privacy_policy.dart';

// ---------------------------------------------------------------- 简易 Markdown

/// 支持的块类型（只够渲染 `assets/privacy.md`，不是完整的 Markdown）。
enum MdKind { h1, h2, h3, paragraph, bullet, numbered, quote, rule }

/// 一个块。[level] 是列表缩进层级（0 起）；[marker] 是有序列表的序号（如 `1.`）。
class MdBlock {
  final MdKind kind;
  final String text;
  final int level;
  final String? marker;

  const MdBlock(this.kind, this.text, {this.level = 0, this.marker});

  @override
  String toString() => 'MdBlock($kind, $level, $marker, $text)';
}

/// 行内片段：普通 / **粗体** / `代码`。
class MdSpan {
  final String text;
  final bool bold;
  final bool code;

  const MdSpan(this.text, {this.bold = false, this.code = false});

  @override
  String toString() => 'MdSpan($text, bold: $bold, code: $code)';
}

final RegExp _numbered = RegExp(r'^(\d+)[.、)]\s+(.*)$');
final RegExp _bullet = RegExp(r'^[-*+]\s+(.*)$');

/// 按行解析：`#`/`##`/`###` 标题、`-`/`*` 无序列表（两个空格一级缩进）、
/// `1.` 有序列表、`>` 引用、`---` 分隔线，其余是段落。
/// 段落与列表项的续行（紧跟着、不是新块开头的行）会接到上一块后面。
List<MdBlock> parseSimpleMarkdown(String source) {
  final blocks = <MdBlock>[];
  MdBlock? open; // 可以接续行的块（段落 / 列表 / 引用）

  void flush() {
    if (open != null) blocks.add(open!);
    open = null;
  }

  for (final rawLine in source.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trimRight();
    final trimmed = line.trimLeft();
    final indent = line.length - trimmed.length;
    if (trimmed.isEmpty) {
      flush();
      continue;
    }
    if (trimmed.startsWith('#')) {
      flush();
      final hashes = RegExp(r'^#+').firstMatch(trimmed)!.group(0)!.length;
      final text = trimmed.substring(hashes).trim();
      final kind = hashes == 1
          ? MdKind.h1
          : (hashes == 2 ? MdKind.h2 : MdKind.h3);
      blocks.add(MdBlock(kind, text));
      continue;
    }
    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
      flush();
      blocks.add(const MdBlock(MdKind.rule, ''));
      continue;
    }
    final bullet = _bullet.firstMatch(trimmed);
    if (bullet != null) {
      flush();
      open = MdBlock(MdKind.bullet, bullet.group(1)!, level: indent ~/ 2);
      continue;
    }
    final numbered = _numbered.firstMatch(trimmed);
    if (numbered != null) {
      flush();
      open = MdBlock(
        MdKind.numbered,
        numbered.group(2)!,
        level: indent ~/ 2,
        marker: '${numbered.group(1)}.',
      );
      continue;
    }
    if (trimmed.startsWith('>')) {
      final text = trimmed.substring(1).trim();
      if (open?.kind == MdKind.quote) {
        open = MdBlock(MdKind.quote, _joinLines(open!.text, text));
      } else {
        flush();
        open = MdBlock(MdKind.quote, text);
      }
      continue;
    }
    // 普通文字：接到当前块后面，没有就开一个段落。
    final current = open;
    if (current != null) {
      open = MdBlock(
        current.kind,
        _joinLines(current.text, trimmed),
        level: current.level,
        marker: current.marker,
      );
    } else {
      open = MdBlock(MdKind.paragraph, trimmed);
    }
  }
  flush();
  return blocks;
}

/// 续行拼接：两边都是 ASCII 字母数字时补一个空格，中文直接接上。
String _joinLines(String a, String b) {
  if (a.isEmpty) return b;
  final last = a.codeUnitAt(a.length - 1);
  final first = b.codeUnitAt(0);
  bool ascii(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x29 ||
      c == 0x2C ||
      c == 0x2E;
  return ascii(last) && ascii(first) ? '$a $b' : '$a$b';
}

/// 行内解析：`**粗体**`、`` `代码` ``；没闭合的标记按普通文字处理。
List<MdSpan> parseInlineMarkdown(String text) {
  final spans = <MdSpan>[];
  final buffer = StringBuffer();
  var i = 0;
  void flushPlain() {
    if (buffer.isNotEmpty) spans.add(MdSpan(buffer.toString()));
    buffer.clear();
  }

  while (i < text.length) {
    if (text.startsWith('**', i)) {
      final end = text.indexOf('**', i + 2);
      if (end > i + 2) {
        flushPlain();
        spans.add(MdSpan(text.substring(i + 2, end), bold: true));
        i = end + 2;
        continue;
      }
    }
    if (text[i] == '`') {
      final end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flushPlain();
        spans.add(MdSpan(text.substring(i + 1, end), code: true));
        i = end + 1;
        continue;
      }
    }
    buffer.write(text[i]);
    i++;
  }
  flushPlain();
  return spans;
}

/// 把解析好的块画出来。
class SimpleMarkdownView extends StatelessWidget {
  final List<MdBlock> blocks;

  const SimpleMarkdownView({super.key, required this.blocks});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final base =
        t.textTheme.bodyMedium?.copyWith(height: 1.6) ??
        const TextStyle(fontSize: 14, height: 1.6);
    final muted = t.colorScheme.onSurfaceVariant;
    final children = <Widget>[];
    for (final b in blocks) {
      switch (b.kind) {
        case MdKind.h1:
          children.add(
            _text(
              b.text,
              base.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
              top: 4,
              bottom: 8,
            ),
          );
        case MdKind.h2:
          children.add(
            _text(
              b.text,
              base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
              top: 16,
              bottom: 6,
            ),
          );
        case MdKind.h3:
          children.add(
            _text(
              b.text,
              base.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
              top: 10,
              bottom: 4,
            ),
          );
        case MdKind.paragraph:
          children.add(_text(b.text, base, bottom: 8));
        case MdKind.quote:
          children.add(
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: t.colorScheme.primary, width: 3),
                ),
                color: t.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
              ),
              child: _rich(b.text, base.copyWith(color: muted)),
            ),
          );
        case MdKind.bullet:
        case MdKind.numbered:
          children.add(
            Padding(
              padding: EdgeInsets.only(left: 4.0 + b.level * 16, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: b.kind == MdKind.bullet ? 16 : 24,
                    child: Text(
                      b.kind == MdKind.bullet ? '•' : b.marker ?? '',
                      style: base,
                    ),
                  ),
                  Expanded(child: _rich(b.text, base)),
                ],
              ),
            ),
          );
        case MdKind.rule:
          children.add(const Divider(height: 24));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _text(
    String text,
    TextStyle style, {
    double top = 0,
    double bottom = 0,
  }) => Padding(
    padding: EdgeInsets.only(top: top, bottom: bottom),
    child: _rich(text, style),
  );

  Widget _rich(String text, TextStyle style) {
    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          for (final s in parseInlineMarkdown(text))
            TextSpan(
              text: s.text,
              style: s.bold
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : (s.code
                        ? const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                          )
                        : null),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 页面

/// 读 `assets/privacy.md`；读不到时给一段兜底文字（不会白屏）。
Future<String> loadPrivacyText(BuildContext context) async {
  try {
    return await DefaultAssetBundle.of(context)
        .loadString(PrivacyPolicy.assetPath);
  } catch (_) {
    return '# 隐私说明\n\n隐私说明文件读取失败。简要说明：${AppBrand.name}不收集、不上传你的课表，'
        '所有数据只保存在这台手机上；只有在你导入课表或检查更新时才会联网。';
  }
}

/// 设置 → 隐私说明。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私说明')),
      body: FutureBuilder<String>(
        future: loadPrivacyText(context),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: <Widget>[
              SimpleMarkdownView(blocks: parseSimpleMarkdown(snap.data!)),
            ],
          );
        },
      ),
    );
  }
}

/// 首次启动的一次性「隐私说明」确认。返回 true = 同意。
///
/// 不能点外面关掉、不能按返回键关掉；「不同意」由调用方决定怎么办（HomeShell 会退出 App）。
Future<bool> showPrivacyConsentDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey<String>('privacy-consent'),
        title: const Text('隐私说明'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('欢迎使用${AppBrand.name}。开始之前请花一分钟了解：'),
              const SizedBox(height: 10),
              const Text('· 课表、作息、设置只保存在这台手机上，没有服务器，不上传。'),
              const Text(
                '· 只在两种情况下联网：你主动「从教务导入」时打开学校的教务网页；'
                '每天最多一次检查新版本（会暴露你的 IP 地址给下载服务器）。',
              ),
              const Text('· 不需要注册账号，不读取通讯录、位置、相册，没有广告和统计 SDK。'),
              const Text('· 教务密码只在学校自己的网页里输入，App 不保存。'),
              const SizedBox(height: 10),
              Text(
                '同意之前，App 不会发出任何网络请求。',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey<String>('privacy-read-full'),
                  onPressed: () => Navigator.of(dialogContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PrivacyPage(),
                    ),
                  ),
                  child: const Text('阅读完整隐私说明'),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('privacy-decline'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('不同意并退出'),
          ),
          FilledButton(
            key: const ValueKey<String>('privacy-accept'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('同意'),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
