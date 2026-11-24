import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/features/import/adapters/school_adapter.dart';
import 'package:shu_schedule/features/import/diagnostics/diagnostic_sample.dart';
import 'package:shu_schedule/features/import/diagnostics/redact.dart';

void main() {
  group('redactSensitive：学号（8~12 位数字）', () {
    test('独立的 8 / 10 / 12 位数字被替换', () {
      expect(redactSensitive('学号 26120001 结束'), '学号 *** 结束');
      expect(redactSensitive('id=2612000123&x=1'), 'id=***&x=1');
      expect(redactSensitive('"XH":"202612000123"'), '"XH":"***"');
    });

    test('7 位 / 13 位（时间戳）不动', () {
      expect(redactSensitive('1234567'), '1234567');
      expect(redactSensitive('t=1790000000000'), 't=1790000000000');
    });

    test('紧挨字母的数字串也算独立（学号常出现在 URL 路径里）', () {
      expect(redactSensitive('/xs/su26120001/kb'), '/xs/su***/kb');
    });
  });

  group('redactSensitive：手机号', () {
    test('11 位、+86、空格 / 短横线分隔都能认', () {
      expect(redactSensitive('电话 13812345678。'), '电话 ***。');
      expect(redactSensitive('tel:+86 138-1234-5678'), 'tel:***');
      expect(redactSensitive('138 1234 5678'), '***');
    });

    test('不是 1[3-9] 开头的 11 位数字仍按学号规则处理', () {
      expect(redactSensitive('10012345678'), '***');
    });
  });

  group('redactSensitive：姓名字段', () {
    test('JSON 里的 xm / XM / xsxm / 姓名 → ***，键名保持原样', () {
      final out = redactSensitive(
        '{"XM":"张三","xm":"王建国, 李梅","xsxm":"赵四","姓名":"钱五","kcmc":"高等数学"}',
      );
      expect(out, contains('"XM":"***"'));
      expect(out, contains('"xm":"***"'));
      expect(out, contains('"xsxm":"***"'));
      expect(out, contains('"姓名":"***"'));
      expect(out, contains('"kcmc":"高等数学"'), reason: '其他字段不动');
      expect(out.contains('张三') || out.contains('王建国'), isFalse);
    });

    test('值里带转义引号也能完整替换', () {
      final out = redactSensitive(r'{"xm":"张\"三\"","x":1}');
      expect(out, r'{"xm":"***","x":1}');
    });

    test('JSON 字符串里再转义一层的 \\"xm\\":\\"…\\"', () {
      final inner = jsonEncode(<String, String>{'XM': '张三', 'kcmc': '线代'});
      final outer = jsonEncode(<String, String>{'sample': inner});
      final out = redactSensitive(outer);
      expect(out.contains('张三'), isFalse);
      expect(out, contains(r'\"XM\":\"***\"'));
      expect(out, contains('线代'));
    });

    test('表单 / 查询串里的 xm=…', () {
      expect(redactSensitive('a=1&xm=%E5%BC%A0&b=2'), 'a=1&xm=***&b=2');
      expect(redactSensitive('?xm=张三'), '?xm=***');
    });

    test('页面文本里的「姓名：…」', () {
      expect(redactSensitive('<td>姓名：张三</td>'), '<td>姓名：***</td>');
      expect(redactSensitive('姓 名: Li Lei'), '姓 名: *** Lei');
    });

    test('extraSecrets：已知的学生姓名在任何位置都被抹掉', () {
      final out = redactSensitive(
        '<span id="user">欢迎你，张三同学</span>',
        extraSecrets: <String>['张三', ' ', '李'],
      );
      expect(out, '<span id="user">欢迎你，***同学</span>');
    });

    test('没有敏感信息的文本原样返回', () {
      const text = '{"kcmc":"大学物理(一)","zcd":"1-8周,10-16周","jcs":"7-8"}';
      expect(redactSensitive(text), text);
    });
  });

  group('truncateUtf8', () {
    test('按字节截断，不切坏中文', () {
      const text = '一二三abc';
      expect(truncateUtf8(text, 100), text);
      expect(truncateUtf8(text, 9), '一二三');
      expect(truncateUtf8(text, 8), '一二', reason: '第 3 个汉字只剩 2 字节，整个丢掉');
      expect(truncateUtf8(text, 10), '一二三a');
      expect(truncateUtf8(text, 0), '');
    });
  });

  group('DiagnosticSample.build', () {
    final now = DateTime(2026, 9, 23, 10, 5, 9);

    test('所有字段都脱敏，头部写明规则', () {
      final text = DiagnosticSample.build(
        const DiagnosticInput(
          schoolId: 'shu',
          schoolName: '上海大学',
          systemType: 'zfsoft',
          status: '已验证',
          url: 'https://jwxt.shu.edu.cn/jwglxt/xtgl/index_initMenu.html?su=26120001',
          stage: 'schedule',
          error: '抓取失败：13812345678',
          response:
              '{"ok":true,"data":{"kb":{"xsxx":{"XM":"张三","XH":"26120001"}}}}',
          pageHtml: '<div>姓名：张三 学号：26120001</div>',
          secrets: <String>['张三'],
        ),
        now: now,
        version: '9.9.9',
      );
      expect(text, contains('# 课表导入记录'));
      expect(text, isNot(contains('诊断样本')));
      expect(text, contains('app: 9.9.9'));
      expect(text, contains('school: shu 上海大学'));
      expect(text, contains('status: 已验证'));
      expect(text, contains('index_initMenu.html?su=***'));
      expect(text, contains('error: 抓取失败：***'));
      expect(text.contains('张三'), isFalse);
      expect(text.contains('26120001'), isFalse);
      expect(text.contains('13812345678'), isFalse);
      expect(text, contains('----- response -----'));
      expect(text, contains('----- page -----'));
    });

    test('每段最多 200KB，先脱敏再截断（截断处不会漏出半个学号）', () {
      // 学号正好跨在 200KB 边界上。
      final pad = 'a' * (DiagnosticSample.maxSectionBytes - 4);
      final text = DiagnosticSample.build(
        DiagnosticInput(response: '${pad}26120001${'b' * 5000}'),
        now: now,
      );
      final section = text
          .split('----- response -----\n')[1]
          .split('\n\n----- page -----')[0];
      expect(
        utf8.encode(section).length,
        lessThanOrEqualTo(DiagnosticSample.maxSectionBytes),
      );
      expect(section.contains('2612'), isFalse);
      expect(section.startsWith('$pad***b'), isTrue);
    });

    test('hasPayload：没有响应也没有页面时为 false', () {
      expect(const DiagnosticInput(schoolId: 'x').hasPayload, isFalse);
      expect(const DiagnosticInput(response: '{}').hasPayload, isTrue);
      expect(const DiagnosticInput(pageHtml: '<html>').hasPayload, isTrue);
    });

    test('文件名只有 ASCII', () {
      expect(
        DiagnosticSample.fileNameFor(now),
        'import-diagnostic-20260923-100509.txt',
      );
    });

    test('真实 fixture：脱敏后课程名、周次都还在，姓名和学号不在', () {
      final raw = File('test/import/fixtures/shu_kb_envelope.json')
          .readAsStringSync(encoding: utf8);
      final out = redactSensitive(raw);
      expect(out.contains('张三'), isFalse);
      expect(out.contains('26120001'), isFalse);
      expect(out.contains('王建国'), isFalse, reason: 'kbList 里的 xm（教师）也按姓名字段处理');
      expect(out, contains('高等数学(一)'));
      expect(out, contains('1-15周(单)'));
      // 脱敏后仍然是合法 JSON，开发者拿到能直接当 fixture 用。
      expect(() => jsonDecode(out), returnsNormally);
    });
  });

  group('通道消息：诊断快照', () {
    test('{diag:true} 识别为 diagnostic，优先于 ok / progress', () {
      expect(
        parseChannelMessage('{"diag":true,"url":"x","html":"<p>"}').kind,
        ChannelMessageKind.diagnostic,
      );
      expect(
        parseChannelMessage('{"diag":true,"ok":true}').kind,
        ChannelMessageKind.diagnostic,
      );
      expect(
        parseChannelMessage('{"diag":"yes","ok":true}').kind,
        ChannelMessageKind.result,
      );
    });
  });
}
