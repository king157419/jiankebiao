import 'package:flutter/material.dart';

import '../../../core/feedback_links.dart';
import '../adapters/school_registry.dart';
import 'web_login_page.dart';

/// 导入流程第一步：选择学校。
class SchoolSelectPage extends StatefulWidget {
  const SchoolSelectPage({super.key});

  @override
  State<SchoolSelectPage> createState() => _SchoolSelectPageState();
}

class _SchoolSelectPageState extends State<SchoolSelectPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  late final Future<void> _loading = SchoolRegistry.ensureLoaded();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(SchoolEntry entry) async {
    final adapter = entry.buildAdapter();
    if (adapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('暂不支持「${systemTypeLabel(entry.type)}」')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebLoginPage(adapter: adapter, status: entry.status),
      ),
    );
  }

  /// 「我的学校不在列表」：输入教务网址 → 按网址特征猜系统类型。
  Future<void> _addByUrl() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('我的学校不在列表'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('输入学校教务系统的网址（登录后浏览器地址栏里的那个）：'),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('custom-school-url'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: '例如 https://jwxt.example.edu.cn/jwglxt',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('下一步'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || !mounted) return;

    final guess = SchoolUrlGuess.fromUrl(input);
    final entry = guess.entry;
    if (entry == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('暂不支持'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(guess.message ?? '无法识别这个教务系统。'),
              const SizedBox(height: 12),
              Text(
                FeedbackLinks.unsupportedSchoolHint,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('识别为正方教务（实验）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('将按正方新版（jwglxt）尝试导入：\n${entry.baseUrl}'),
            const SizedBox(height: 8),
            Text(
              '这所学校没有人验证过，导入结果请逐条核对。导入失败时可以导出导入记录反馈给开发者。',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            if (guess.message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                guess.message!,
                style: Theme.of(ctx).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(ctx).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (go == true && mounted) await _open(entry);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('导入课表')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索学校（名称 / 拼音 / 简称）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text('怎么导入', style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. 选择学校，App 会打开学校教务系统的登录页。\n'
                      '2. 用学校的账号登录（可能需要手机或企业微信二次验证）。\n'
                      '3. 登录进教务系统后，点底部的「一键导入课表」。\n\n'
                      '整个过程只在你自己的手机上完成，账号密码不会经过任何服务器。',
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<void>(
              future: _loading,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final schools = SchoolRegistry.search(_query);
                return ListView(
                  children: <Widget>[
                    if (schools.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('没有匹配的学校')),
                      ),
                    for (final s in schools) ...<Widget>[
                      _SchoolTile(entry: s, onTap: () => _open(s)),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      leading: const Icon(Icons.add_link),
                      title: const Text('我的学校不在列表'),
                      subtitle: const Text('输入教务系统网址，按系统类型尝试导入'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _addByUrl,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SchoolTile extends StatelessWidget {
  const _SchoolTile({required this.entry, required this.onTap});

  final SchoolEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          entry.name.isEmpty ? '?' : entry.name.substring(0, 1),
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
        ),
      ),
      title: Row(
        children: <Widget>[
          Flexible(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          SchoolStatusChip(status: entry.status),
        ],
      ),
      subtitle: Text(entry.description),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// 学校验证状态的小标签。
class SchoolStatusChip extends StatelessWidget {
  const SchoolStatusChip({super.key, required this.status});

  final SchoolStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      SchoolStatus.verified => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      SchoolStatus.community => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      SchoolStatus.experimental => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
    };
    return Semantics(
      label: '验证状态：${status.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          status.label,
          style: TextStyle(fontSize: 11, color: fg, height: 1.3),
        ),
      ),
    );
  }
}
