import 'package:cqut_lab_schedule/models/course.dart';
import 'package:cqut_lab_schedule/models/term_calendar.dart';
import 'package:cqut_lab_schedule/services/regular_schedule_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses exported section times and expands the exact teaching weeks', () {
    final courses = parseRegularSchedule('''
      {
        "courses": [{
          "name": "大学英语", "position": "弘远楼 A0201", "teacher": "王老师",
          "day": 4, "startSection": 1, "endSection": 2, "weeks": [2, 4, 4, 6]
        }],
        "timeSlots": [
          {"number": 2, "startTime": "09:25", "endTime": "10:10"},
          {"number": 1, "startTime": "8:30", "endTime": "09:15"}
        ]
      }
    ''');

    expect(courses.map((course) => course.week), [2, 4, 6]);
    final entry = courses.first;
    expect(entry.kind, CourseKind.regular);
    expect((entry.name, entry.weekday), ('大学英语', 4));
    expect((entry.startTime, entry.endTime), ('08:30', '10:10'));
    expect((entry.location, entry.teacher), ('弘远楼 A0201', '王老师'));
  });

  test('uses custom times for a course without section numbers', () {
    final course = parseRegularSchedule('''
      {"courses": [{
        "name": "辅导答疑", "day": 6, "weeks": [17], "isCustomTime": true,
        "customStartTime": "19:00", "customEndTime": "20:35"
      }], "timeSlots": []}
    ''').single;

    expect((course.startTime, course.endTime), ('19:00', '20:35'));
  });

  test('uses real dates and traverses calendar year boundaries', () {
    final calendar = TermCalendar.cqutFall2026;

    expect(calendar.weekOf(DateTime(2026, 11, 14)), 11);
    expect(calendar.mondayForWeek(11), DateTime.utc(2026, 11, 9));
    expect(calendar.weekOf(DateTime(2027, 1, 1)), 18);
    expect(calendar.mondayForWeek(19), DateTime.utc(2027, 1, 4));
    expect(calendar.weekOf(DateTime(2026, 8, 30)), 0);
  });

  test('uses imported semester start date when available', () {
    final imported = parseRegularScheduleImport('''
      {"courses": [{
        "name": "大学英语", "day": 6, "weeks": [17], "isCustomTime": true,
        "customStartTime": "19:00", "customEndTime": "20:35"
      }], "config": {"semesterStartDate":"2027-02-24","semesterTotalWeeks":20}}
    ''');

    expect(imported.courses.single.week, 17);
    expect(imported.calendar?.firstMonday, DateTime.utc(2027, 2, 22));
    expect(imported.calendar?.totalWeeks, 20);
    expect(
      TermCalendar.fromConfig(imported.calendar?.toConfig())?.totalWeeks,
      20,
    );
    expect(
      TermCalendar.fromConfig({'semesterStartDate': '2027-02-30'}),
      isNull,
    );
  });

  test('rejects an unresolved timetable instead of guessing a class time', () {
    expect(
      () => parseRegularSchedule('''
        {"courses": [{"name": "大学英语", "day": 4,
          "startSection": 1, "endSection": 2, "weeks": [4]}],
         "timeSlots": [{"number": 1, "startTime": "08:30", "endTime": "09:15"}]}
      '''),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('大学英语'),
        ),
      ),
    );
    expect(() => parseRegularSchedule('{"meta": {}}'), throwsFormatException);
    expect(() => parseRegularSchedule('not JSON'), throwsFormatException);
  });
}
