import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show CachingAssetBundle, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/theme/app_theme.dart';
import 'package:shu_schedule/core/theme/theme_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeRegistry', () {
    test('assets/themes/themes.json 能解析出 6 套主题', () async {
      final text = await rootBundle.loadString(ThemeRegistry.assetPath);
      final themes = ThemeRegistry.parse(text);

      expect(themes.length, 6);
      expect(themes.map((t) => t.id).toList(), <String>[
        'sakura',
        'mint',
        'cream',
        'blueberry',
        'galaxy',
        'shu',
      ]);
      for (final t in themes) {
        expect(t.name, isNotEmpty, reason: '${t.id} 缺少名称');
        expect(t.description, isNotEmpty, reason: '${t.id} 缺少描述');
        expect(t.courseColors.length, 10, reason: '${t.id} 课程色不是 10 个');
        expect(t.courseColors.toSet().length, 10, reason: '${t.id} 课程色有重复');
        expect(t.cornerRadius, greaterThan(0));
        expect(t.blockOpacity, inInclusiveRange(0.1, 1.0));
      }
      // 两套深色主题。
      expect(themes.where((t) => t.isDark).map((t) => t.id).toList(), <String>[
        'blueberry',
        'galaxy',
      ]);
    });

    test('load() 在读不到 asset 时回退到内置「经典蓝」', () async {
      final themes = await ThemeRegistry.load(bundle: _BrokenBundle());
      expect(themes.length, 1);
      expect(themes.first.id, 'shu');
      expect(themes.first.name, '经典蓝');
    });

    test('顶层不是数组时 parse 抛 FormatException', () {
      expect(() => ThemeRegistry.parse('{"a":1}'), throwsFormatException);
    });

    test('单条主题损坏时只跳过那一条', () {
      final themes = ThemeRegistry.parse(
        '[{"name":"没有 id"},{"id":"x","name":"能用"}]',
      );
      expect(themes.length, 1);
      expect(themes.first.id, 'x');
    });

    test('resolve() 找不到 id 时回退到 shu', () {
      final themes = ThemeRegistry.parse(
        '[{"id":"a"},{"id":"shu"},{"id":"b"}]',
      );
      expect(ThemeRegistry.resolve(themes, 'b').id, 'b');
      expect(ThemeRegistry.resolve(themes, 'default').id, 'shu');
      expect(ThemeRegistry.resolve(themes, null).id, 'shu');
      expect(ThemeRegistry.resolve(const <AppTheme>[], 'a').id, 'shu');
    });

    test('背景插画路径映射到打包的 webp', () async {
      final text = await rootBundle.loadString(ThemeRegistry.assetPath);
      final themes = ThemeRegistry.parse(text);
      final sakura = themes.firstWhere((t) => t.id == 'sakura');
      expect(sakura.backgroundAssetPath, 'assets/images/sakura_bg.webp');
      // 这三张图必须真的打包进去了。
      for (final id in <String>['sakura', 'mint', 'galaxy']) {
        final path = themes.firstWhere((t) => t.id == id).backgroundAssetPath!;
        expect(await rootBundle.load(path), isNotNull, reason: '$path 缺失');
      }
      final shu = themes.firstWhere((t) => t.id == 'shu');
      expect(shu.backgroundAssetPath, isNull);
    });
  });

  group('AppTheme', () {
    test(
      'toThemeData 映射 Material 3 ColorScheme，深色主题 brightness=dark',
      () async {
        final text = await rootBundle.loadString(ThemeRegistry.assetPath);
        final themes = ThemeRegistry.parse(text);
        for (final t in themes) {
          final data = t.toThemeData();
          expect(data.useMaterial3, isTrue);
          expect(
            data.colorScheme.brightness,
            t.isDark ? Brightness.dark : Brightness.light,
            reason: '${t.id} brightness 不对',
          );
          expect(data.colorScheme.primary, t.colors.primary);
          expect(data.scaffoldBackgroundColor, t.colors.background);
        }
      },
    );

    test('courseColor 越界取模，不崩溃', () {
      expect(builtinShuTheme.courseColor(0), builtinShuTheme.courseColors[0]);
      expect(builtinShuTheme.courseColor(12), builtinShuTheme.courseColors[2]);
      expect(builtinShuTheme.courseColor(-1), builtinShuTheme.courseColors[9]);
    });

    test('parseHexColor 容错', () {
      expect(
        parseHexColor('#FF0000', fallback: const Color(0xFF000000)),
        const Color(0xFFFF0000),
      );
      expect(
        parseHexColor('zzz', fallback: const Color(0xFF123456)),
        const Color(0xFF123456),
      );
      expect(
        parseHexColor(null, fallback: const Color(0xFF123456)),
        const Color(0xFF123456),
      );
      expect(hexOf(const Color(0xFF1F4E9C)), '#1F4E9C');
    });
  });
}

/// 永远读不到东西的 bundle，用来验证回退逻辑。
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw Exception('no asset');
}
