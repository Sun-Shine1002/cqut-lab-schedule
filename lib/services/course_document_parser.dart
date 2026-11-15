import '../models/course.dart';
import '../models/timetable_periods.dart';

class CourseDocumentClass {
  const CourseDocumentClass({
    required this.courses,
    this.alternatives = const [],
  });

  final List<Course> courses;

  /// Each group contains interchangeable source rows. One row can cover
  /// several weeks, so its occurrences must be selected together.
  final List<List<List<Course>>> alternatives;
}

/// Parses class schedules from structured workbook sheets or Word tables.
/// Row values are indexed by column, including cells filled from merged ranges.
Map<String, CourseDocumentClass> parseCourseDocumentTables(
  Map<String, List<List<String>>> sheets,
) {
  final groups = <String, _ClassSchedule>{};

  for (final MapEntry(key: title, value: rows) in sheets.entries) {
    var classContext = _classContext(title);
    var labContext = _labTitle.hasMatch(_headerText(title));
    _TableHeader? header;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final textCells = row
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      if (textCells.length == 1) {
        final caption = textCells.single;
        classContext = _classContext(caption) ?? classContext;
        labContext = labContext || _labTitle.hasMatch(_headerText(caption));
      }

      final singleHeader = _readHeader(row);
      if (singleHeader.isComplete) {
        header = singleHeader;
        continue;
      }
      if (index + 1 < rows.length && singleHeader.columns.length >= 2) {
        final joined = _readHeader(row, rows[index + 1]);
        if (joined.isComplete) {
          header = joined;
          index++;
          continue;
        }
      }

      if (header == null) continue;
      final columns = header.columns;
      String raw(_Column column) => _at(row, columns[column]);
      String value(_Column column) => _text(raw(column));

      final rawGroups = columns.containsKey(_Column.group)
          ? raw(_Column.group)
          : classContext ?? '';
      final classNames = _classNames(rawGroups);
      final name = value(_Column.name);
      final project = value(_Column.project);
      final weekNumbers = _readWeeks(raw(_Column.week));
      final day = _readWeekday(value(_Column.weekday));
      final times = _readTime(
        start: value(_Column.start),
        end: value(_Column.end),
        range: value(_Column.time),
        section: value(_Column.section),
      );
      if (classNames.isEmpty ||
          name.isEmpty ||
          weekNumbers.isEmpty ||
          day == null ||
          times == null) {
        continue;
      }

      final (start, end) = times;
      final room = value(_Column.room);
      final teacher = value(_Column.teacher);
      final kind = switch (value(_Column.kind)) {
        '实验' || '实验课' || '实验课程' || '课内实验' => CourseKind.lab,
        '正课' || '理论课' || '理论' || '普通课' => CourseKind.regular,
        _ => labContext || header.isLab ? CourseKind.lab : CourseKind.regular,
      };
      final label =
          kind == CourseKind.lab && project.isNotEmpty && project != name
          ? '$name · $project'
          : name;
      final weeks = weekNumbers.toList()..sort();
      final occurrences = [
        for (final week in weeks)
          Course(
            kind: kind,
            name: label,
            week: week,
            weekday: day,
            startTime: start,
            endTime: end,
            location: room,
            teacher: teacher,
          ),
      ];
      for (final className in classNames) {
        groups
            .putIfAbsent(className, _ClassSchedule.new)
            .addRow(
              occurrences,
              project: kind == CourseKind.lab && project.isNotEmpty
                  ? label
                  : null,
              rowKey: (weeks.join(','), day, start, end, room, teacher),
            );
      }
    }
  }

  return Map.unmodifiable(
    groups.map((key, schedule) => MapEntry(key, schedule.toResult())),
  );
}

typedef _RowKey = (String, int, String, String, String, String);
typedef _OccurrenceKey = (
  CourseKind,
  String,
  int,
  int,
  String,
  String,
  String,
  String,
);

class _ClassSchedule {
  final _courses = <_OccurrenceKey, Course>{};
  final _projectRows = <String, Map<_RowKey, List<Course>>>{};

  void addRow(
    List<Course> occurrences, {
    required String? project,
    required _RowKey rowKey,
  }) {
    if (project == null) {
      _addCourses(occurrences);
    } else {
      _projectRows
          .putIfAbsent(project, () => {})
          .putIfAbsent(rowKey, () => occurrences);
    }
  }

  void _addCourses(List<Course> occurrences) {
    for (final course in occurrences) {
      final key = (
        course.kind,
        course.name,
        course.week,
        course.weekday,
        course.startTime,
        course.endTime,
        course.location,
        course.teacher,
      );
      _courses.putIfAbsent(key, () => course);
    }
  }

  CourseDocumentClass toResult() {
    final alternatives = <List<List<Course>>>[];
    for (final rows in _projectRows.values) {
      if (rows.length == 1) {
        _addCourses(rows.values.single);
      } else {
        alternatives.add(
          List.unmodifiable(rows.values.map(List<Course>.unmodifiable)),
        );
      }
    }
    return CourseDocumentClass(
      courses: List.unmodifiable(_courses.values),
      alternatives: List.unmodifiable(alternatives),
    );
  }
}

enum _Column {
  name,
  project,
  kind,
  group,
  week,
  weekday,
  time,
  section,
  start,
  end,
  room,
  teacher,
}

const _headings = <String, _Column>{
  '课程名称': _Column.name,
  '课程': _Column.name,
  '课名': _Column.name,
  '教学课程': _Column.name,
  '实验名称': _Column.name,
  '实验课程': _Column.name,
  '实验项目': _Column.project,
  '实验项目名称': _Column.project,
  '课程类型': _Column.kind,
  '课程类别': _Column.kind,
  '类型': _Column.kind,
  '专业班级': _Column.group,
  '班级': _Column.group,
  '教学班': _Column.group,
  '行政班': _Column.group,
  '行政班级': _Column.group,
  '班级名称': _Column.group,
  '周次': _Column.week,
  '周': _Column.week,
  '开课周次': _Column.week,
  '上课周次': _Column.week,
  '实验周次': _Column.week,
  '教学周': _Column.week,
  '星期': _Column.weekday,
  '星期几': _Column.weekday,
  '周几': _Column.weekday,
  '上课星期': _Column.weekday,
  '实验星期': _Column.weekday,
  '时间': _Column.time,
  '上课时间': _Column.time,
  '实验时间': _Column.time,
  '时间段': _Column.time,
  '上课时段': _Column.time,
  '节次': _Column.section,
  '上课节次': _Column.section,
  '课节': _Column.section,
  '开始': _Column.start,
  '开始时间': _Column.start,
  '上课开始时间': _Column.start,
  '结束': _Column.end,
  '结束时间': _Column.end,
  '上课结束时间': _Column.end,
  '教室': _Column.room,
  '地点': _Column.room,
  '上课地点': _Column.room,
  '上课教室': _Column.room,
  '实验地点': _Column.room,
  '实验室': _Column.room,
  '实验室房间': _Column.room,
  '教师': _Column.teacher,
  '老师': _Column.teacher,
  '任课教师': _Column.teacher,
  '授课教师': _Column.teacher,
  '指导教师': _Column.teacher,
};

class _TableHeader {
  const _TableHeader(this.columns, {required this.isLab});

  final Map<_Column, int> columns;
  final bool isLab;

  bool get isComplete =>
      columns.containsKey(_Column.name) &&
      columns.containsKey(_Column.week) &&
      columns.containsKey(_Column.weekday) &&
      (columns.containsKey(_Column.time) ||
          columns.containsKey(_Column.section) ||
          (columns.containsKey(_Column.start) &&
              columns.containsKey(_Column.end)));
}

_TableHeader _readHeader(List<String> top, [List<String> bottom = const []]) {
  final columns = <_Column, int>{};
  var isLab = false;
  for (var i = 0; i < top.length || i < bottom.length; i++) {
    final first = _headerText(_at(top, i));
    final second = _headerText(_at(bottom, i));
    for (final heading in ['$first$second', first, second]) {
      final column = _headings[heading];
      if (column == null) continue;
      columns.putIfAbsent(column, () => i);
      isLab = isLab || heading.startsWith('实验');
      break;
    }
  }
  return _TableHeader(columns, isLab: isLab);
}

String _at(List<String> row, int? index) =>
    index != null && index < row.length ? row[index] : '';

final _whitespace = RegExp(r'[\s\u00a0\u3000]+');
final _cjkSpaces = RegExp(r'(?<=[\u3400-\u9fff]) +(?=[\u3400-\u9fff])');
final _labTitle = RegExp(r'课内实验|实验课表|实验课程(?:安排表?|表)|实验教学(?:课表|安排表)');
final _classCaption = RegExp(r'^(?:专业|行政)?班级\s*[:：]\s*(.+)$', dotAll: true);
final _classSeparators = RegExp(r'[,，、;；\r\n]+');

String? _classContext(String value) =>
    _classCaption.firstMatch(value.trim())?.group(1);

Set<String> _classNames(String raw) => raw
    .split(_classSeparators)
    .map(_text)
    .where((part) => part.isNotEmpty && part.length <= 80)
    .toSet();

String _text(String value) =>
    value.replaceAll(_whitespace, ' ').trim().replaceAll(_cjkSpaces, '');

String _headerText(String value) =>
    _asciiWidth(value).replaceAll(_whitespace, '');

String _asciiWidth(String value) => String.fromCharCodes(
  value.codeUnits.map(
    (unit) => unit >= 0xff01 && unit <= 0xff5e ? unit - 0xfee0 : unit,
  ),
);

final _weekPart = RegExp(
  r'^(\d{1,2})(?:[-‐‑–—−~至到](\d{1,2}))?(?:\(([单双])\)|([单双]))?$',
);

Set<int> _readWeeks(String raw) {
  final text = _headerText(raw.replaceAll(RegExp(r'[\r\n]+'), ','))
      .replaceAll(RegExp(r'[第周]'), '');
  final weeks = <int>{};
  for (final part in text.split(_classSeparators)) {
    final match = _weekPart.firstMatch(part);
    if (match == null) return {};
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2) ?? match.group(1)!);
    if (start < 1 || end > 53 || start > end) return {};
    final parity = match.group(3) ?? match.group(4);
    for (var week = start; week <= end; week++) {
      if (parity == null || week.isOdd == (parity == '单')) weeks.add(week);
    }
  }
  return weeks;
}

final _day = RegExp(r'^(?:星期|周|礼拜)?([一二三四五六日天1-7])$');
const _dayNumbers = {
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '日': 7,
  '天': 7,
};

int? _readWeekday(String raw) {
  final day = _day.firstMatch(_headerText(raw))?.group(1);
  return day == null ? null : _dayNumbers[day] ?? int.tryParse(day);
}

final _clock = RegExp(r'^(\d{1,2}):([0-5]\d)$');
final _excelTime = RegExp(r'^0(?:\.\d+)?$');
final _timeRange = RegExp(r'^(\d{1,2}:\d{2})(?:[-‐‑–—−~至到]+)(\d{1,2}:\d{2})$');
final _sectionRange = RegExp(r'^(\d{1,2})(?:[-‐‑–—−~至到](\d{1,2}))?$');

(String, String)? _readTime({
  required String start,
  required String end,
  required String range,
  required String section,
}) {
  if (start.isNotEmpty || end.isNotEmpty) {
    return _validateTime(_readClock(start), _readClock(end));
  }
  final match = _timeRange.firstMatch(
    _headerText(range.isEmpty ? section : range),
  );
  if (match != null)
    return _validateTime(
      _readClock(match.group(1)!),
      _readClock(match.group(2)!),
    );

  final slots = _sectionRange.firstMatch(
    _headerText(section).replaceAll(RegExp(r'[第节]'), ''),
  );
  if (slots == null || range.isNotEmpty) return null;
  final first = int.parse(slots.group(1)!);
  final last = int.parse(slots.group(2) ?? slots.group(1)!);
  if (first < 1 || last < first || last > twoRiversPeriods.length) return null;
  return (
    timetableClockText(twoRiversPeriods[first - 1].$1),
    timetableClockText(twoRiversPeriods[last - 1].$2),
  );
}

String? _readClock(String raw) {
  final text = _headerText(raw);
  final match = _clock.firstMatch(text);
  if (match != null) {
    final hour = int.parse(match.group(1)!);
    if (hour < 24)
      return '${hour.toString().padLeft(2, '0')}:${match.group(2)}';
  }
  if (_excelTime.hasMatch(text)) {
    final minutes = (double.parse(text) * 1440).round();
    if (minutes < 1440) return timetableClockText(minutes);
  }
  return null;
}

(String, String)? _validateTime(String? start, String? end) =>
    start != null && end != null && start.compareTo(end) < 0
    ? (start, end)
    : null;
