import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/features/timetable/course_detail_sheet.dart';
import 'package:shu_schedule/models/timetable.dart';

void main() {
  String? names(String id) => const <String, String>{'shu': '上海大学'}[id];

  test('手动 / 备份 / 不认识的值', () {
    expect(courseSourceLabel('manual'), '手动添加');
    expect(courseSourceLabel('backup'), '来自备份恢复');
    expect(courseSourceLabel(''), '手动添加');
    expect(courseSourceLabel('Something Else'), '手动添加');
  });

  test('1.2.0 的旧值 zfsoft-shu 仍显示为教务导入', () {
    expect(courseSourceLabel('zfsoft-shu'), '来自教务系统导入');
    expect(
      courseSourceLabel('zfsoft-shu', schoolNameOf: names),
      '来自教务系统导入（上海大学）',
    );
  });

  test('新来源标记 systemType-schoolId：任意学校、任意系统', () {
    expect(
      courseSourceLabel(Timetable.sourceTagOf('zfsoft', 'custom-jw.a.edu.cn')),
      '来自教务系统导入',
    );
    expect(
      courseSourceLabel('qiangzhi-shu', schoolNameOf: names),
      '来自教务系统导入（上海大学）',
    );
    expect(
      courseSourceLabel('zfsoft-unknown', schoolNameOf: names),
      '来自教务系统导入',
      reason: '查不到校名时不带括号',
    );
  });

  test('Timetable.sourceTagOf 是唯一拼法，和 sourceTag getter 一致', () {
    expect(Timetable.sourceTagOf('zfsoft', 'shu'), 'zfsoft-shu');
    final tt = Timetable.empty()
      ..systemType = 'zfsoft'
      ..schoolId = 'x';
    expect(tt.sourceTag, Timetable.sourceTagOf('zfsoft', 'x'));
  });
}
