import '../models/course.dart';

class LabCourseDraft {
  const LabCourseDraft({
    this.name = '',
    this.week,
    this.weekday,
    this.startTime,
    this.endTime,
    this.location = '',
    this.teacher = '',
    this.grade,
    this.evaluation = '',
    this.sourceText = '',
  });

  final String name;
  final int? week;
  final int? weekday;
  final String? startTime;
  final String? endTime;
  final String location;
  final String teacher;
  final String? grade;
  final String evaluation;
  final String sourceText;

  bool get isNameOnly =>
      name.isNotEmpty &&
      week == null &&
      weekday == null &&
      startTime == null &&
      endTime == null &&
      location.isEmpty &&
      teacher.isEmpty &&
      grade == null &&
      evaluation.isEmpty;

  bool get isDetailsOnly =>
      name.isEmpty &&
      week != null &&
      weekday != null &&
      startTime != null &&
      endTime != null;

  LabCourseDraft withNameFrom(LabCourseDraft label) => LabCourseDraft(
    name: label.name,
    week: week,
    weekday: weekday,
    startTime: startTime,
    endTime: endTime,
    location: location,
    teacher: teacher,
    grade: grade,
    evaluation: evaluation,
    sourceText: '${label.sourceText}\n$sourceText',
  );

  Course? toCourse() {
    final courseName = name.trim();
    final courseWeek = week;
    final courseWeekday = weekday;
    final start = _readClock(startTime ?? '');
    final end = _readClock(endTime ?? '');
    if (courseName.isEmpty ||
        courseWeek == null ||
        courseWeek < 1 ||
        courseWeek > 53 ||
        courseWeekday == null ||
        courseWeekday < 1 ||
        courseWeekday > 7 ||
        start == null ||
        end == null ||
        start.compareTo(end) >= 0) {
      return null;
    }
    final score = grade?.trim();
    return Course(
      name: courseName,
      week: courseWeek,
      weekday: courseWeekday,
      startTime: start,
      endTime: end,
      location: location.trim(),
      teacher: teacher.trim(),
      grade: score == null || score.isEmpty ? null : score,
      evaluation: evaluation.trim(),
      kind: CourseKind.lab,
    );
  }
}

final _clock = RegExp(r'^(\d{1,2})\s*:\s*(\d{2})$');
final _range = RegExp(
  r'(?<!\d)(\d{1,2}\s*:\s*\d{2})\s*(?:[-‐‑–—−~～至到]\s*)?'
  r'(\d{1,2}\s*:\s*\d{2})(?!\d)',
);
final _explicitWeek = RegExp(r'第\s*(\d{1,2})\s*周?$|(?<!\d)(\d{1,2})\s*周$');
final _plainWeek = RegExp(r'(?:^|\s)(\d{1,2})$');
final _joinedWeek = RegExp(r'(?<=[\u3400-\u9fff])(\d{1,2})$');
final _explicitDay = RegExp(r'(?:星\s*期|周|礼\s*拜)\s*([一二三四五六日天1-7])$');
final _plainDay = RegExp(r'(?:^|\s)([一二三四五六日天])$');
final _numericDay = RegExp(r'\s([1-7])$');
const _weekdays = {
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '日': 7,
  '天': 7,
};
final _status = RegExp(r'(未评教|已评教|待评教|未评价|已评价)$');
final _score = RegExp(r'^(\d{1,3}(?:\.\d+)?|优秀|良好|合格|及格|不及格)$');
final _location = RegExp(
  r'^(.*?(?:楼|实验室|校区|教室|操场|场馆|馆)\s*[A-Za-z]?\s*\d+[A-Za-z0-9-]*(?:室)?|[A-Za-z]\d{2,}[A-Za-z0-9-]*)',
);
final _person = RegExp(r'^[\u3400-\u9fff·]{2,4}$');
final _cjkSpace = RegExp(r'(?<=[\u3400-\u9fff]) +(?=[\u3400-\u9fff])');
final _text = RegExp(r'[A-Za-z\u3400-\u9fff]');
final _tableSeparators = RegExp(r'[\t|｜]+');
final _multiSpace = RegExp(r' {2,}');

/// Converts OCR rows into editable candidates. Tab-delimited cells preserve
/// table boundaries, while the time range anchors rows from plain OCR text.
List<LabCourseDraft> parseLabScreenshot(String text) {
  final lines = _normalize(text)
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList();
  final nameHeader = lines.indexWhere((line) => _cleanText(line) == '实验名称');
  if (nameHeader >= 0 && !lines.any(_range.hasMatch)) {
    return [
      for (final line in lines.skip(nameHeader + 1))
        if (_isName(line.trim()))
          LabCourseDraft(name: _cleanText(line), sourceText: line.trim()),
    ];
  }
  final drafts = <LabCourseDraft>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    // Some engines return each table cell on its own line.
    if (index + 3 < lines.length &&
        _isName(line.trim()) &&
        _parseWeek(lines[index + 1].trim()) != null &&
        _parseDay(lines[index + 2].trim(), allowNumber: true) != null &&
        _range.matchAsPrefix(lines[index + 3].trim()) != null) {
      final row = lines.sublist(index, index + 4);
      index += 3;
      if (index + 1 < lines.length &&
          _location.hasMatch(lines[index + 1].trim())) {
        row.add(lines[++index]);
        if (index + 1 < lines.length &&
            _person.hasMatch(lines[index + 1].trim()) &&
            (index + 2 == lines.length ||
                _parseWeek(lines[index + 2].trim()) == null)) {
          row.add(lines[++index]);
        }
        if (index + 1 < lines.length &&
            _score.hasMatch(lines[index + 1].trim()) &&
            (index + 2 == lines.length ||
                _parseDay(lines[index + 2].trim()) == null)) {
          row.add(lines[++index]);
        }
        if (index + 1 < lines.length &&
            _status.hasMatch(lines[index + 1].trim())) {
          row.add(lines[++index]);
        }
      }
      final draft = _parseRow(row.join('\t'));
      if (draft != null) drafts.add(draft);
      continue;
    }
    final draft = _parseRow(line);
    if (draft != null) drafts.add(draft);
  }
  return drafts;
}

LabCourseDraft? _parseRow(String line) {
  final range = _range.firstMatch(line);
  final cells = line
      .split(_tableSeparators)
      .map((part) => part.trim())
      .toList();
  if (range == null) {
    // An unreadable time cell should not discard the rest of a structured row.
    if (cells.length < 3 || !_isName(cells.first)) return null;
    final week = _parseWeek(cells[1]);
    final weekday = _parseDay(cells[2], allowNumber: true);
    if (week == null && weekday == null) return null;
    final (location, teacher, grade, evaluation) = _readDetails(cells.skip(4));
    return LabCourseDraft(
      name: _cleanText(cells.first),
      week: week,
      weekday: weekday,
      location: location,
      teacher: teacher,
      grade: grade,
      evaluation: evaluation,
      sourceText: line.trim(),
    );
  }

  final prefixCells = line
      .substring(0, range.start)
      .trimRight()
      .split(_tableSeparators);
  var prefix = prefixCells.join(' ').trim();
  final numericDay =
      prefixCells.length >= 3 &&
          _parseWeek(prefixCells[prefixCells.length - 2].trim()) != null
      ? _numericDay.firstMatch(prefix)
      : null;
  final explicitDay = _explicitDay.firstMatch(prefix);
  final dayMatch = explicitDay ?? _plainDay.firstMatch(prefix) ?? numericDay;
  final weekday = _parseDay(
    dayMatch?.group(0)?.trim() ?? '',
    allowNumber: numericDay != null,
  );
  if (dayMatch != null) prefix = prefix.substring(0, dayMatch.start).trim();
  final weekMatch =
      _explicitWeek.firstMatch(prefix) ??
      _plainWeek.firstMatch(prefix) ??
      (explicitDay == null ? null : _joinedWeek.firstMatch(prefix));
  final week = weekMatch == null
      ? null
      : _parseWeek(weekMatch.group(0)!.trim());
  final name = weekMatch == null
      ? prefix
      : prefix.substring(0, weekMatch.start).trim();

  final suffix = line.substring(range.end).trimLeft();
  final (location, teacher, grade, evaluation) = _readDetails(
    suffix.split(
      suffix.contains(_tableSeparators) ? _tableSeparators : _multiSpace,
    ),
  );
  final hasName = _isName(name);
  if ((week == null && weekday == null && location.isEmpty) ||
      (!hasName &&
          location.isEmpty &&
          (cells.length < 3 || week == null || weekday == null))) {
    return null;
  }
  return LabCourseDraft(
    name: hasName ? _cleanText(name) : '',
    week: week,
    weekday: weekday,
    startTime: _readClock(range.group(1)!),
    endTime: _readClock(range.group(2)!),
    location: location,
    teacher: teacher,
    grade: grade,
    evaluation: evaluation,
    sourceText: line.trim(),
  );
}

(String, String, String?, String) _readDetails(Iterable<String> parts) {
  final cells = parts.map(_cleanText).where((part) => part.isNotEmpty).toList();
  if (cells.isEmpty) return ('', '', null, '');

  var evaluation = '';
  final status = _status.firstMatch(cells.last);
  if (status != null) {
    evaluation = status.group(0)!;
    final beforeStatus = cells.removeLast().substring(0, status.start).trim();
    if (beforeStatus.isNotEmpty) cells.add(beforeStatus);
  }
  var location = '';
  var teacher = '';
  String? grade;
  for (final cell in cells) {
    final room = _location.firstMatch(cell);
    if (location.isEmpty && room != null) {
      location = room.group(0)!;
      final tail = cell.substring(room.end).trim().split(RegExp(r' +'));
      if (_person.hasMatch(tail.first) && !_score.hasMatch(tail.first)) {
        teacher = tail.first;
      }
      if (_score.hasMatch(tail.last)) grade = tail.last;
    } else if (location.isNotEmpty &&
        teacher.isEmpty &&
        _person.hasMatch(cell) &&
        !_score.hasMatch(cell)) {
      teacher = cell;
    } else if (_score.hasMatch(cell)) {
      grade = cell;
    }
  }
  return (location, teacher, grade, evaluation);
}

bool _isName(String value) =>
    _text.hasMatch(value) &&
    !RegExp(r'[:\t|｜]|^(?:实验名称|实验课表|物理实验课表|物理实验演示课表|课程表|更新时间|课表时间|上课时间)')
        .hasMatch(value);

int? _parseWeek(String value) {
  final match = _explicitWeek.firstMatch(value) ?? _plainWeek.firstMatch(value);
  if (match == null || match.start != 0) return null;
  final week = int.tryParse(match.group(1) ?? match.group(2)!);
  return week != null && week >= 1 && week <= 53 ? week : null;
}

int? _parseDay(String value, {bool allowNumber = false}) {
  final match = _explicitDay.firstMatch(value) ?? _plainDay.firstMatch(value);
  final day = match?.start == 0 ? match!.group(1) : null;
  final number = int.tryParse(day ?? (allowNumber ? value : ''));
  return _weekdays[day] ??
      (number != null && number >= 1 && number <= 7 ? number : null);
}

String _cleanText(String value) => value.trim().replaceAll(_cjkSpace, '');

String? _readClock(String value) {
  final match = _clock.firstMatch(_normalize(value).trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _normalize(String value) => String.fromCharCodes(
  value.codeUnits.map(
    (unit) => switch (unit) {
      >= 0xff01 && <= 0xff5e => unit - 0xfee0,
      0x3000 || 0x00a0 => 0x20,
      _ => unit,
    },
  ),
);
