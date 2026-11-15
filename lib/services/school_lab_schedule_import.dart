import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/course.dart';
import 'schedule_parser.dart';

const _channel = MethodChannel('com.cqutlabs.cqut_lab_schedule/lab_import');

bool get supportsSchoolLabScheduleImport =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<List<Course>?> importSchoolLabSchedule() async {
  final reader = await rootBundle.loadString('assets/cqut_lab_import.js');
  final result = await _channel.invokeMethod<String>('open', reader);
  return result == null ? null : parseSchoolLabScheduleRows(result);
}

List<Course> parseSchoolLabScheduleRows(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const FormatException('学校实验课表的读取结果格式不正确');
  }
  if (decoded is! List || decoded.length > 200) {
    throw const FormatException('学校实验课表的读取结果格式不正确');
  }

  final parser = ScheduleParser();
  final courses = <Course>[];
  for (final row in decoded) {
    if (row is! List ||
        row.length != 6 ||
        !row.every((field) => field is String && field.length <= 160)) {
      continue;
    }
    try {
      courses.add(parser.parseCourseFields(row.cast<String>()));
    } on FormatException {
      continue;
    }
  }
  if (courses.isEmpty && decoded.isNotEmpty) {
    throw const FormatException('未读取到可识别的实验课程');
  }
  return List.unmodifiable(courses);
}
