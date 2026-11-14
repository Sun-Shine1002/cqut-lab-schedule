import 'dart:convert';

import '../models/course.dart';
import '../models/term_calendar.dart';

class RegularScheduleImport {
  const RegularScheduleImport({required this.courses, this.calendar});

  final List<Course> courses;
  final TermCalendar? calendar;
}

List<Course> parseRegularSchedule(String source) =>
    parseRegularScheduleImport(source).courses;

/// Reads courses and any term dates from a school import or 拾光课程表 export.
RegularScheduleImport parseRegularScheduleImport(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(
      source.startsWith('\ufeff') ? source.substring(1) : source,
    );
  } on FormatException {
    throw const FormatException('无法读取学校课表数据，请重新导入。');
  }
  if (decoded is! Map<String, dynamic> || decoded['courses'] is! List) {
    throw const FormatException('课表数据缺少课程列表，请重新导入。');
  }
  final entries = decoded['courses'] as List;
  if (entries.isEmpty) throw const FormatException('课表中没有正课可导入。');

  final slots = _parseTimeSlots(decoded['timeSlots']);
  final result = <Course>[];
  final seen = <(String, int, int, String, String, String, String)>{};
  for (final (index, entry) in entries.indexed) {
    final row = index + 1;
    if (entry is! Map<String, dynamic>) {
      throw FormatException('第 $row 条课程的格式不正确。');
    }
    final name = _optionalText(entry['name']);
    final location = _optionalText(entry['position']);
    final teacher = _optionalText(entry['teacher']);
    final day = entry['day'];
    final weeks = entry['weeks'];
    if (name.isEmpty) throw FormatException('第 $row 条课程缺少名称。');
    if (day is! int || day < 1 || day > 7) {
      throw FormatException('「$name」的星期不正确。');
    }
    if (weeks is! List ||
        weeks.isEmpty ||
        weeks.any((week) => week is! int || week < 1 || week > 53)) {
      throw FormatException('「$name」的周次不正确。');
    }

    final (start, end) = _readCourseTime(entry, slots, name);
    for (final week in weeks.cast<int>()) {
      if (!seen.add((name, week, day, start, end, location, teacher))) continue;
      result.add(
        Course(
          name: name,
          week: week,
          weekday: day,
          startTime: start,
          endTime: end,
          location: location,
          teacher: teacher,
          kind: CourseKind.regular,
        ),
      );
    }
  }
  return RegularScheduleImport(
    courses: List.unmodifiable(result),
    calendar: TermCalendar.fromConfig(decoded['config']),
  );
}

Map<int, (String, String)> _parseTimeSlots(Object? value) {
  if (value == null) return {};
  if (value is! List) throw const FormatException('课表中的节次时间表格式不正确。');
  final slots = <int, (String, String)>{};
  for (final entry in value) {
    if (entry is! Map<String, dynamic>) {
      throw const FormatException('课表中的节次时间表格式不正确。');
    }
    final number = entry['number'];
    final start = _readClock(entry['startTime']);
    final end = _readClock(entry['endTime']);
    if (number is! int ||
        number < 1 ||
        slots.containsKey(number) ||
        start == null ||
        end == null ||
        start.compareTo(end) >= 0) {
      throw const FormatException('课表中的节次编号或时间不正确。');
    }
    slots[number] = (start, end);
  }
  return slots;
}

(String, String) _readCourseTime(
  Map<String, dynamic> course,
  Map<int, (String, String)> slots,
  String name,
) {
  final String? start;
  final String? end;
  if (course['isCustomTime'] == true) {
    start = _readClock(course['customStartTime']);
    end = _readClock(course['customEndTime']);
  } else {
    final first = course['startSection'];
    final last = course['endSection'];
    if (first is! int || last is! int || first < 1 || last < first) {
      throw FormatException('「$name」的节次不正确。');
    }
    start = slots[first]?.$1;
    end = slots[last]?.$2;
    if (start == null || end == null) {
      throw FormatException('课表中缺少「$name」对应节次的时间。');
    }
  }
  if (start == null || end == null || start.compareTo(end) >= 0) {
    throw FormatException('「$name」的上课时间不正确。');
  }
  return (start, end);
}

String _optionalText(Object? value) => value is String ? value.trim() : '';

final _clock = RegExp(r'^(\d{1,2}):([0-5]\d)$');

String? _readClock(Object? value) {
  if (value is! String) return null;
  final match = _clock.firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  if (hour > 23) return null;
  return '${hour.toString().padLeft(2, '0')}:${match.group(2)}';
}
