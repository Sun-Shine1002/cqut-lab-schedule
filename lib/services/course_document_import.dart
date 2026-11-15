import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'course_document_parser.dart';
import 'course_document_tables.dart';

const _documentTypes = [
  XTypeGroup(
    label: 'Excel 和 Word 课表',
    extensions: ['xlsx', 'docx'],
    mimeTypes: [
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ],
    uniformTypeIdentifiers: [
      'org.openxmlformats.spreadsheetml.sheet',
      'org.openxmlformats.wordprocessingml.document',
    ],
  ),
];

Future<Map<String, CourseDocumentClass>?> chooseCourseDocument() async {
  final file = await openFile(acceptedTypeGroups: _documentTypes);
  if (file == null) return null;

  final length = await file.length();
  if (length == 0 || length > maxCourseDocumentBytes) {
    throw const FormatException('请选择 8 MB 以内的有效 Excel 或 Word 文件。');
  }
  final bytes = await file.readAsBytes();
  return compute(_parseDocument, (bytes, file.name));
}

Map<String, CourseDocumentClass> _parseDocument((Uint8List, String) file) {
  final tables = readCourseDocumentTables(file.$1, file.$2);
  final courses = parseCourseDocumentTables(tables);
  if (courses.isEmpty) {
    throw const FormatException('未找到可导入的课程。请检查表格中的班级、课程、周次、星期和上课时间。');
  }
  return courses;
}
