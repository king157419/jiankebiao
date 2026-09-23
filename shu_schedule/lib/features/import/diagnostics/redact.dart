import 'dart:convert';

/// 诊断样本的本地脱敏（纯函数，有单测）。
///
/// 规则：
/// 1. [extraSecrets] 里的字面量（例如已经解析出来的学生姓名）→ `***`；
/// 2. 姓名字段的值 → `***`：JSON 里的 `"xm" / "xsxm" / "姓名"`（键名大小写不敏感，
///    也认 JSON 字符串里再转义一层的 `\"xm\":\"…\"`）、表单 / 查询串里的 `xm=…`、
///    页面文本里的 `姓名：…`；
/// 3. 11 位手机号（可带 `+86`、空格或短横线分隔）→ `***`；
/// 4. 独立的 8~12 位数字（学号 / 工号 / 身份证号的一部分）→ `***`。
///    前后紧挨着别的数字时不算「独立」，所以 13 位时间戳不会被拆开误伤。
///
/// 注意：规则 4 也会把 8 位课程号、`20260914` 这种日期替换掉，这是故意的——
/// 宁可样本里少一点信息，也不要漏掉学号。
String redactSensitive(
  String text, {
  Iterable<String> extraSecrets = const <String>[],
}) {
  var out = text;

  // 1. 已知的敏感字面量（长的先换，避免短的把长的切开）。
  final secrets =
      extraSecrets
          .map((s) => s.trim())
          .where((s) => s.length >= 2)
          .toSet()
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  for (final s in secrets) {
    out = out.replaceAll(s, redactedMark);
  }

  // 2. 姓名字段。
  out = out.replaceAllMapped(
    _jsonNameField,
    (m) => '"${m[1]}":"$redactedMark"',
  );
  out = out.replaceAllMapped(
    _escapedJsonNameField,
    (m) => '\\"${m[1]}\\":\\"$redactedMark\\"',
  );
  out = out.replaceAllMapped(
    _formNameField,
    (m) => '${m[1]}${m[2]}=$redactedMark',
  );
  out = out.replaceAllMapped(_labelNameField, (m) => '${m[1]}$redactedMark');

  // 3. 手机号（先于 4，11 位手机号本身也会被 4 命中，但带分隔符的只有这里能认）。
  out = out.replaceAll(_phone, redactedMark);

  // 4. 8~12 位独立数字。
  out = out.replaceAll(_longDigits, redactedMark);
  return out;
}

/// 替换后的占位符。
const String redactedMark = '***';

const String _nameKeys = r'(?:xm|xsxm|姓名)';

final RegExp _jsonNameField = RegExp(
  '"($_nameKeys)"\\s*:\\s*"(?:[^"\\\\]|\\\\.)*"',
  caseSensitive: false,
);

final RegExp _escapedJsonNameField = RegExp(
  r'\\"(' + _nameKeys + r')\\"\s*:\s*\\"(?:(?!\\").)*\\"',
  caseSensitive: false,
);

final RegExp _formNameField = RegExp(
  r'(^|[?&;\s])(' + _nameKeys + r')=[^&\s"<>]*',
  caseSensitive: false,
  multiLine: true,
);

final RegExp _labelNameField = RegExp(r'(姓\s*名\s*[:：]\s*)[^\s<>"，,;；]+');

final RegExp _phone = RegExp(
  r'(?<!\d)(?:\+?86[\s-]?)?1[3-9]\d(?:[\s-]?\d{4}){2}(?!\d)',
);

final RegExp _longDigits = RegExp(r'(?<!\d)\d{8,12}(?!\d)');

/// 按 UTF-8 字节数截断，不切坏多字节字符。没超过 [maxBytes] 原样返回。
String truncateUtf8(String text, int maxBytes) {
  if (maxBytes <= 0) return '';
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return text;
  var end = maxBytes;
  // 往回退到一个字符的起始字节（UTF-8 续字节是 10xxxxxx）。
  while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
    end--;
  }
  return utf8.decode(bytes.sublist(0, end));
}
