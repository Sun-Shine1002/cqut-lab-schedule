import 'package:html/parser.dart' as html;

import '../models/course.dart';

typedef ScheduleRowIssue = ({int rowNumber, String reason});

class ScheduleParseResult {
  ScheduleParseResult(List<Course> courses, List<ScheduleRowIssue> issues)
    : courses = List.unmodifiable(courses),
      issues = List.unmodifiable(issues);

  final List<Course> courses;

  /// Row numbers are one-based and include the header.
  final List<ScheduleRowIssue> issues;
}

class ScheduleParser {
  static final _spaces = RegExp(r'[\s\u00a0\u3000]+');
  static final _week = RegExp(r'^(?:第\s*)?([0-9]+)(?:\s*周)?$');
  static final _weekday = RegExp(r'^(?:星期|周)?\s*([一二三四五六日天])$');
  static const _weekdays = {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
  };
  static final _timeRange = RegExp(
    r'^([0-9]{1,2})[:：]([0-9]{2})\s*[-－‐‑–—−~～至]\s*'
    r'([0-9]{1,2})[:：]([0-9]{2})$',
  );

  /// Throws [FormatException] when the file has no matching table.
  ScheduleParseResult parse(String source) {
    final table = html.parse(source).querySelector('table#RpCourse');
    if (table == null) {
      throw const FormatException('未找到实验课表（RpCourse）');
    }

    const sections = {'tbody', 'thead', 'tfoot'};
    final rows = table.children
        .expand(
          (element) => sections.contains(element.localName)
              ? element.children
              : [element],
        )
        .where((element) => element.localName == 'tr');
    final courses = <Course>[];
    final issues = <ScheduleRowIssue>[];

    for (final (index, row) in rows.indexed.skip(1)) {
      final cells = row.children
          .where((cell) => cell.localName == 'td')
          .map((cell) => cell.text.replaceAll(_spaces, ' ').trim())
          .toList();
      try {
        courses.add(_parseRow(cells));
      } on FormatException catch (error) {
        issues.add((rowNumber: index + 1, reason: error.message));
      }
    }

    return ScheduleParseResult(courses, issues);
  }

  Course _parseRow(List<String> cells) {
    if (cells.length != 9) {
      throw const FormatException('实验课表应有 9 列');
    }
    if (cells[0].isEmpty) {
      throw const FormatException('缺少实验名称');
    }

    final week = int.tryParse(_week.firstMatch(cells[1])?.group(1) ?? '');
    if (week == null || week <= 0) {
      throw const FormatException('实验周次无效');
    }
    final weekday = _weekdays[_weekday.firstMatch(cells[2])?.group(1)];
    if (weekday == null) {
      throw const FormatException('实验星期无效');
    }

    final range = _timeRange.firstMatch(cells[3]);
    if (range == null) {
      throw const FormatException('实验时间格式无效');
    }
    final start = _minutes(range.group(1)!, range.group(2)!);
    final end = _minutes(range.group(3)!, range.group(4)!);
    if (start >= end) {
      throw const FormatException('实验结束时间应晚于开始时间');
    }

    return Course(
      kind: CourseKind.lab,
      name: cells[0],
      week: week,
      weekday: weekday,
      startTime: _clockText(start),
      endTime: _clockText(end),
      location: cells[4],
      teacher: cells[5],
      grade: cells[6].isEmpty ? null : cells[6],
      evaluation: cells[8],
    );
  }

  int _minutes(String hourText, String minuteText) {
    final hour = int.parse(hourText);
    final minute = int.parse(minuteText);
    if (hour > 23 || minute > 59) {
      throw const FormatException('实验时间超出有效范围');
    }
    return hour * 60 + minute;
  }

  String _clockText(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
