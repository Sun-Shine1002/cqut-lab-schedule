import 'dart:convert';

import 'package:cqut_lab_schedule/models/course.dart';
import 'package:cqut_lab_schedule/services/school_lab_schedule_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports only the six timetable fields and keeps valid rows', () {
    final courses = parseSchoolLabScheduleRows(
      jsonEncode([
        ['错误课次', '第零周', '星期三', '16:20-18:35', '明理楼201', '张明'],
        ['成绩行', '4', '四', '16:20-18:35', '明理楼201', '张明', '90'],
        ['错误字段', '4', '四', '16:20-18:35', '明理楼201', false],
        ['扭摆实验', '第 4 周', '星期三', '16:20 — 18:35', '明理楼201', '张明'],
      ]),
    );
    final course = courses.single;
    expect(course.kind, CourseKind.lab);
    expect(course.name, '扭摆实验');
    expect(course.week, 4);
    expect(course.weekday, 3);
    expect(course.startTime, '16:20');
    expect(course.endTime, '18:35');
    expect(course.location, '明理楼201');
    expect(course.teacher, '张明');
    expect(course.grade, isNull);
    expect(course.evaluation, isEmpty);
  });

  test('distinguishes the explicit empty result from malformed rows', () {
    expect(parseSchoolLabScheduleRows('[]'), isEmpty);
    expect(() => parseSchoolLabScheduleRows('[[]]'), throwsFormatException);
    expect(
      () => parseSchoolLabScheduleRows(
        jsonEncode([
          ['过长的名称' * 40, '4', '四', '16:20-18:35', '', ''],
        ]),
      ),
      throwsFormatException,
    );
  });

  test('invalid JSON does not attach sensitive input to the exception', () {
    expect(
      () => parseSchoolLabScheduleRows('{password: private}'),
      throwsA(
        isA<FormatException>()
            .having((error) => error.source, 'source', isNull)
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('private')),
            ),
      ),
    );
  });
}
