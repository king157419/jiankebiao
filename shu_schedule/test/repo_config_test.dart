import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/feedback_links.dart';
import 'package:shu_schedule/core/holiday_repository.dart';
import 'package:shu_schedule/core/repo_config.dart';

/// v1.4.0 A1：发布仓库一处配置（`lib/core/repo_config.dart`）。
void main() {
  group('RepoConfig.rawUrls', () {
    test('没配 Gitee：2 个地址，jsDelivr 在前、raw.githubusercontent 在后', () {
      const repo = RepoConfig(githubOwner: 'me', githubRepo: 'jkb');
      expect(repo.hasGitee, isFalse);
      expect(
        repo.rawUrls('shu_schedule/assets/holidays.json').map((u) => '$u'),
        <String>[
          'https://cdn.jsdelivr.net/gh/me/jkb@main/shu_schedule/assets/holidays.json',
          'https://raw.githubusercontent.com/me/jkb/main/shu_schedule/assets/holidays.json',
        ],
      );
    });

    test('配了 Gitee：3 个地址，Gitee raw 在最前；分支可改；开头的 / 去掉', () {
      const repo = RepoConfig(
        githubOwner: 'me',
        githubRepo: 'jkb',
        giteeOwner: 'me-cn',
        giteeRepo: 'jkb-mirror',
        branch: 'release',
      );
      expect(repo.hasGitee, isTrue);
      final urls = repo.rawUrls('/latest.json');
      expect(urls, hasLength(3));
      expect(urls.map((u) => u.host).toList(), <String>[
        'gitee.com',
        'cdn.jsdelivr.net',
        'raw.githubusercontent.com',
      ]);
      expect(
        urls.first.toString(),
        'https://gitee.com/me-cn/jkb-mirror/raw/release/latest.json',
      );
      expect(
        urls[1].toString(),
        'https://cdn.jsdelivr.net/gh/me/jkb@release/latest.json',
      );
      expect(
        urls[2].toString(),
        'https://raw.githubusercontent.com/me/jkb/release/latest.json',
      );
      expect(urls.every((u) => u.scheme == 'https'), isTrue);
    });

    test('只填了一半的 Gitee 不算配置', () {
      const repo = RepoConfig(
        githubOwner: 'me',
        githubRepo: 'jkb',
        giteeOwner: 'me-cn',
      );
      expect(repo.hasGitee, isFalse);
      expect(repo.rawUrls('latest.json'), hasLength(2));
    });
  });

  group('占位符', () {
    test('OWNER / REPO / 空串都算占位符；真实仓库不算', () {
      expect(
        const RepoConfig(githubOwner: 'OWNER', githubRepo: 'jkb').isPlaceholder,
        isTrue,
      );
      expect(
        const RepoConfig(githubOwner: 'me', githubRepo: 'REPO').isPlaceholder,
        isTrue,
      );
      expect(
        const RepoConfig(githubOwner: '', githubRepo: 'jkb').isPlaceholder,
        isTrue,
      );
      expect(
        const RepoConfig(githubOwner: 'me', githubRepo: ' ').isPlaceholder,
        isTrue,
      );
      const real = RepoConfig(githubOwner: 'me', githubRepo: 'jkb');
      expect(real.isPlaceholder, isFalse);
      expect(real.isConfigured, isTrue);
      expect(real.issuesUrl, 'https://github.com/me/jkb/issues');
    });

    test('当前 kRepo 还是占位符：反馈链接、假日表仓库都从它派生', () {
      expect(kRepo.isPlaceholder, isTrue);
      expect(FeedbackLinks.issuesUrl, kRepo.issuesUrl);
      expect(FeedbackLinks.isConfigured, isFalse);
      expect(HolidayRepository().repo, same(kRepo));
    });

    test('lib/ 里只有 repo_config.dart 写着 OWNER / REPO 占位符', () {
      final offenders = <String>[];
      final pattern = RegExp(r"OWNER|'REPO'|/REPO\b");
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final path = f.path.replaceAll(r'\', '/');
        if (path.endsWith('lib/core/repo_config.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) {
            offenders.add('$path:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
      final config = File('lib/core/repo_config.dart').readAsStringSync();
      expect(
        config,
        contains("const RepoConfig kRepo = RepoConfig(githubOwner: 'OWNER', "),
      );
    });
  });
}
