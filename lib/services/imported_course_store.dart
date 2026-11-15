import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import '../models/term_calendar.dart';

class ImportedCourseStore {
  ImportedCourseStore(this.kind);

  final CourseKind kind;
  String get _key => 'imported_${kind.name}_courses_v1';
  static const _snapshotKey = 'imported_courses_snapshot_v1';
  static final _clock = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
  static SharedPreferencesAsync get _preferences => SharedPreferencesAsync();
  static Future<void> _pendingWrite = Future<void>.value();

  Future<({List<Course> courses, TermCalendar? calendar})>
  loadWithCalendar() async {
    final snapshot = await _readSnapshot();
    return _loadSection(snapshot);
  }

  Future<({List<Course> courses, TermCalendar? calendar})> _loadSection(
    Map<String, dynamic> snapshot,
  ) async {
    if (snapshot.containsKey(kind.name)) {
      return _decodeSection(snapshot[kind.name]);
    }
    final legacy = await _preferences.getString(_key);
    return _decodeSection(
      legacy == null ? const <Object?>[] : jsonDecode(legacy),
    );
  }

  ({List<Course> courses, TermCalendar? calendar}) _decodeSection(
    Object? input,
  ) {
    final (records, calendar) = switch (input) {
      List<dynamic> records => (records, null),
      {'courses': List<dynamic> courses, 'config': final config} => (
        courses,
        TermCalendar.fromConfig(config),
      ),
      _ => throw const FormatException('本地课程记录格式有误。'),
    };
    return (
      courses: records
          .map((record) => _decode(record as Map<String, dynamic>))
          .toList(),
      calendar: calendar,
    );
  }

  Future<List<Course>> add(List<Course> courses) => _write((snapshot) async {
    final existing = await _loadSection(snapshot);
    final merged = _merge(existing.courses, courses);
    snapshot[kind.name] = _encodeSection(merged, existing.calendar);
    return merged;
  });

  static Future<CourseBackupData> addCoursesByKind(List<Course> courses) =>
      _write((snapshot) async {
        final regular = await ImportedCourseStore(CourseKind.regular)
            ._loadSection(snapshot);
        final lab = await ImportedCourseStore(CourseKind.lab)
            ._loadSection(snapshot);
        final incomingRegular = courses.where(
          (course) => course.kind == CourseKind.regular,
        );
        final incomingLabs = courses.where(
          (course) => course.kind == CourseKind.lab,
        );
        final mergedRegular = incomingRegular.isEmpty
            ? regular.courses
            : _merge(regular.courses, incomingRegular, keepExisting: true);
        final mergedLabs = incomingLabs.isEmpty
            ? lab.courses
            : _merge(lab.courses, incomingLabs, keepExisting: true);
        if (incomingRegular.isNotEmpty) {
          snapshot[CourseKind.regular.name] = _encodeSection(
            mergedRegular,
            regular.calendar,
          );
        }
        if (incomingLabs.isNotEmpty) {
          snapshot[CourseKind.lab.name] = _encodeSection(
            mergedLabs,
            lab.calendar,
          );
        }
        return CourseBackupData(
          regularCourses: mergedRegular,
          labCourses: mergedLabs,
          termCalendar: regular.calendar,
        );
      });

  static List<Course> _merge(
    Iterable<Course> existing,
    Iterable<Course> incoming, {
    bool keepExisting = false,
  }) {
    (String, int, int, String, String) key(Course course) => (
      course.name.trim().replaceAll(RegExp(r'\s+'), ''),
      course.week,
      course.weekday,
      course.startTime,
      course.endTime,
    );

    final merged = {for (final course in existing) key(course): course};
    for (final course in incoming) {
      if (keepExisting) {
        merged.putIfAbsent(key(course), () => course);
      } else {
        merged[key(course)] = course;
      }
    }
    return merged.values.toList();
  }

  Future<void> replace(List<Course> courses, {TermCalendar? calendar}) =>
      _write((snapshot) async {
        snapshot[kind.name] = _encodeSection(courses, calendar);
      });

  static Future<CourseBackupData> readBackup() async {
    final snapshot = await _readSnapshot();
    final regular = await ImportedCourseStore(CourseKind.regular)
        ._loadSection(snapshot);
    final lab = await ImportedCourseStore(CourseKind.lab)
        ._loadSection(snapshot);
    return CourseBackupData(
      regularCourses: regular.courses,
      labCourses: lab.courses,
      termCalendar: regular.calendar ?? TermCalendar.cqutFall2026,
    );
  }

  static Future<void> restoreBackup(CourseBackupData data) =>
      _write((snapshot) async {
        snapshot[CourseKind.regular.name] = _encodeSection(
          data.regularCourses,
          data.termCalendar,
        );
        snapshot[CourseKind.lab.name] = _encodeSection(data.labCourses, null);
      });

  static Future<Map<String, dynamic>> _readSnapshot() async {
    final source = await _preferences.getString(_snapshotKey);
    if (source == null) return {};
    return jsonDecode(source) as Map<String, dynamic>;
  }

  // Commit both kinds in one write. Serialize imports and restores so an
  // overlapping read-modify-write cannot discard the other operation.
  static Future<T> _write<T>(Future<T> Function(Map<String, dynamic>) change) {
    final next = _pendingWrite.then((_) async {
      final snapshot = await _readSnapshot();
      final result = await change(snapshot);
      await _preferences.setString(_snapshotKey, jsonEncode(snapshot));
      return result;
    });
    _pendingWrite = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  static Object _encodeSection(List<Course> courses, TermCalendar? calendar) {
    final records = courses.map(_encode).toList();
    return calendar == null
        ? records
        : {'courses': records, 'config': calendar.toConfig()};
  }

  static Map<String, Object?> _encode(Course course) => {
    'name': course.name,
    'week': course.week,
    'weekday': course.weekday,
    'startTime': course.startTime,
    'endTime': course.endTime,
    'location': course.location,
    'teacher': course.teacher,
    'grade': course.grade,
    'evaluation': course.evaluation,
  };

  Course _decode(Map<String, dynamic> record) {
    final course = Course(
      kind: kind,
      name: record['name'] as String,
      week: record['week'] as int,
      weekday: record['weekday'] as int,
      startTime: record['startTime'] as String,
      endTime: record['endTime'] as String,
      location: record['location'] as String,
      teacher: record['teacher'] as String,
      grade: record['grade'] as String?,
      evaluation: record['evaluation'] as String,
    );
    if (course.name.trim().isEmpty ||
        course.week < 1 ||
        course.week > 53 ||
        course.weekday < 1 ||
        course.weekday > 7 ||
        !_clock.hasMatch(course.startTime) ||
        !_clock.hasMatch(course.endTime) ||
        course.startTime.compareTo(course.endTime) >= 0) {
      throw const FormatException('本地课程记录格式有误。');
    }
    return course;
  }
}

class CourseBackupData {
  const CourseBackupData({
    required this.regularCourses,
    required this.labCourses,
    required this.termCalendar,
  });

  final List<Course> regularCourses;
  final List<Course> labCourses;
  final TermCalendar? termCalendar;

  String encode() => jsonEncode({
    'format': 'cqut-schedule-backup',
    'version': 1,
    'regular': regularCourses.map(ImportedCourseStore._encode).toList(),
    'lab': labCourses.map(ImportedCourseStore._encode).toList(),
    'term': termCalendar?.toConfig(),
  });

  static CourseBackupData decode(String source) {
    const message = '无法读取课表备份，请选择从本应用导出的 JSON 文件。';
    try {
      final decoded = jsonDecode(source);
      if (decoded case {
        'format': 'cqut-schedule-backup',
        'version': 1,
        'regular': List<dynamic> regular,
        'lab': List<dynamic> lab,
        'term': final term,
      }) {
        final calendar = TermCalendar.fromConfig(term);
        if (term != null &&
            (calendar == null ||
                (term is Map &&
                    term.containsKey('semesterTotalWeeks') &&
                    calendar.totalWeeks == null))) {
          throw const FormatException(message);
        }
        return CourseBackupData(
          regularCourses: List.unmodifiable(
            ImportedCourseStore(CourseKind.regular)
                ._decodeSection(regular)
                .courses,
          ),
          labCourses: List.unmodifiable(
            ImportedCourseStore(CourseKind.lab)._decodeSection(lab).courses,
          ),
          termCalendar: calendar,
        );
      }
    } on FormatException {
      throw const FormatException(message);
    } on TypeError {
      throw const FormatException(message);
    }
    throw const FormatException(message);
  }
}
