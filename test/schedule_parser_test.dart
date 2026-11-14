import 'dart:io';

import 'package:cqut_lab_schedule/services/schedule_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = ScheduleParser();

  test('parses all fields of the eight outline examples', () async {
    final source = await File('assets/demo_schedule.html').readAsString();
    final result = parser.parse(source);

    expect(result.issues, isEmpty);
    expect(
      result.courses.map(
        (course) => (
          course.name,
          course.week,
          course.weekday,
          course.startTime,
          course.endTime,
          course.location,
          course.teacher,
          course.grade,
          course.evaluation,
        ),
      ),
      [
        ('扭摆法测物体转动惯量', 4, 3, '16:20', '18:35', '明理楼201', '张明', null, '未评教'),
        ('双棱镜干涉', 4, 4, '13:50', '16:05', '明理楼302', '李华', null, '未评教'),
        ('波尔共振', 5, 3, '13:50', '16:05', '明理楼305', '李华', null, '未评教'),
        ('组装惠斯登电桥测电阻', 5, 4, '16:20', '18:35', '明理楼108', '李华', null, '未评教'),
        ('RLC串联谐振', 6, 3, '13:50', '16:05', '明理楼106', '张明', null, '未评教'),
        ('霍尔位移传感器测杨氏模量', 6, 5, '13:50', '16:05', '明理楼210', '张明', null, '未评教'),
        ('光学综合实验', 7, 2, '16:20', '18:35', '明理楼211', '张明', null, '未评教'),
        ('光栅衍射', 7, 3, '13:50', '16:05', '明理楼301', '陈静', null, '未评教'),
      ],
    );
  });

  test('normalizes whitespace, week, Sunday, and time variants', () {
    final result = parser.parse('''
      <table><tr><td>无关表格</td></tr></table>
      <table id="RpCourse">
        <thead><tr><th>实验名称</th></tr></thead>
        <tbody><tr>
          <td>&nbsp; 测量　实验 </td><td>第&nbsp; 8 周</td><td>周天</td>
          <td>8：05 — 10:10</td><td>明理楼201</td><td>张明</td>
          <td> 95&nbsp;</td><td>忽略内容</td><td><a>已评教</a></td>
        </tr></tbody>
      </table>
      ''');

    expect(result.issues, isEmpty);
    final course = result.courses.single;
    expect(course.name, '测量 实验');
    expect(course.week, 8);
    expect(course.weekday, 7);
    expect(course.startTime, '08:05');
    expect(course.endTime, '10:10');
    expect(course.grade, '95');
    expect(course.evaluation, '已评教');
  });

  test('reports malformed rows and preserves valid rows', () {
    final result = parser.parse('''
      <table id="RpCourse">
        <tr><th>实验名称</th></tr>
        <tr><td>缺列</td></tr>
        ${_row(week: '0')}
        ${_row(day: '星期八')}
        ${_row(time: '24:00-25:00')}
        ${_row(time: '16:00-14:00')}
        ${_row(time: '下午')}
        ${_row(name: '&nbsp;')}
        ${_row(day: '一')}
        ${_row(day: '六')}
        ${_row(day: '星期日')}
      </table>
      ''');

    expect(result.issues.map((issue) => issue.rowNumber), [
      2,
      3,
      4,
      5,
      6,
      7,
      8,
    ]);
    expect(result.courses.map((course) => course.weekday), [1, 6, 7]);
  });

  test('rejects a page without RpCourse', () {
    expect(() => parser.parse('<form>统一身份认证</form>'), throwsFormatException);
  });

  test('returns an empty list for a table containing only headers', () {
    final result = parser.parse(
      '<table id="RpCourse"><tr><th>实验名称</th></tr></table>',
    );
    expect(result.courses, isEmpty);
    expect(result.issues, isEmpty);
  });
}

String _row({
  String name = '测试实验',
  String week = '1',
  String day = '三',
  String time = '13:50-16:05',
}) =>
    '<tr><td>$name</td><td>$week</td><td>$day</td><td>$time</td>'
    '<td>明理楼201</td><td>张明</td><td></td><td></td><td></td></tr>';
