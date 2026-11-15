import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'course_document_parser.dart';
import 'course_document_tables.dart';

class SharedCourseDocument {
  const SharedCourseDocument({this.classes, this.error});

  final Map<String, CourseDocumentClass>? classes;
  final String? error;
}

class CourseDocumentSharing {
  const CourseDocumentSharing();

  static const _channel = MethodChannel(
    'com.cqutlabs.cqut_lab_schedule/course_document',
  );

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void listen(VoidCallback? onFileAvailable) {
    _channel.setMethodCallHandler(
      onFileAvailable == null
          ? null
          : (call) async {
              if (call.method == 'sharedFileAvailable') onFileAvailable();
            },
    );
  }

  Future<void> openMessagingApp(String source) =>
      _channel.invokeMethod<void>('openMessagingApp', source);

  Future<SharedCourseDocument?> takeSharedFile() async {
    try {
      final document = await _channel.invokeMapMethod<String, Object?>(
        'takeSharedFile',
      );
      if (document == null) return null;
      if (document case {
        'name': final String name,
        'bytes': final Uint8List bytes,
      }) {
        final classes = await compute(_parseDocument, (bytes, name));
        return SharedCourseDocument(classes: classes);
      }
      return const SharedCourseDocument(error: '未收到有效的课表文件，请重新打开附件。');
    } on MissingPluginException {
      return null;
    } on Exception catch (error) {
      return SharedCourseDocument(
        error: switch (error) {
          FormatException(:final message) when message.isNotEmpty => message,
          PlatformException(:final message?) when message.isNotEmpty => message,
          _ => '无法读取共享的课表文件，请重新打开附件。',
        },
      );
    }
  }
}

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
