import 'dart:convert';

import 'package:cqut_lab_schedule/models/course.dart';
import 'package:cqut_lab_schedule/models/term_calendar.dart';
import 'package:cqut_lab_schedule/services/course_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final original = CourseBackupData(
    regularCourses: const [
      Course(
        name: '大学物理',
        week: 11,
        weekday: 3,
        startTime: '10:30',
        endTime: '12:10',
        location: '弘远楼',
        teacher: '',
        kind: CourseKind.regular,
      ),
    ],
    labCourses: const [
      Course(
        name: '大学物理实验',
        week: 11,
        weekday: 5,
        startTime: '13:50',
        endTime: '16:05',
        location: '明理楼',
        teacher: '李华',
        grade: '良好',
        evaluation: '已评教',
      ),
    ],
    termCalendar: TermCalendar.cqutFall2026,
  );

  test('round-trips both course kinds and the term calendar', () {
    final restored = CourseBackupData.decode(original.encode());

    expect(restored.encode(), original.encode());
    expect(restored.regularCourses.single.kind, CourseKind.regular);
    expect(restored.labCourses.single.kind, CourseKind.lab);
    expect(restored.termCalendar?.weekOf(DateTime.utc(2026, 11, 14)), 11);
  });

  test('rejects a backup with invalid data in either section', () {
    final damaged = jsonDecode(original.encode()) as Map<String, dynamic>;
    damaged['lab'][0]['weekday'] = 8;
    expect(
      () => CourseBackupData.decode(jsonEncode(damaged)),
      throwsFormatException,
    );
    expect(
      () => CourseBackupData.decode('{"courses":[]}'),
      throwsFormatException,
    );
  });
}
