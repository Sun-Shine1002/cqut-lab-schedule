import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'imported_course_store.dart';

export 'imported_course_store.dart' show CourseBackupData;

class CourseBackupService {
  const CourseBackupService();

  static const _channel = MethodChannel(
    'com.cqutlabs.cqut_lab_schedule/course_backup_files',
  );
  static const _maxBytes = 2 * 1024 * 1024;
  static const _fileName = '重庆理工大学课表备份.json';
  static const _sizeError = FormatException('请选择 2 MB 以内的有效课表备份。');
  static const _jsonTypes = [
    XTypeGroup(
      label: '课表备份 JSON',
      extensions: ['json'],
      mimeTypes: ['application/json'],
    ),
  ];

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> export() async {
    final backup = await ImportedCourseStore.readBackup();
    if (backup.regularCourses.isEmpty && backup.labCourses.isEmpty) {
      throw const FormatException('请先导入正课或实验课，再创建备份。');
    }
    final bytes = Uint8List.fromList(utf8.encode(backup.encode()));
    if (bytes.length > _maxBytes) throw _sizeError;
    if (_isAndroid) {
      return await _channel.invokeMethod<bool>('save', bytes) ?? false;
    }
    final location = await getSaveLocation(
      suggestedName: _fileName,
      acceptedTypeGroups: _jsonTypes,
    );
    if (location == null) return false;
    await XFile.fromData(
      bytes,
      name: _fileName,
      mimeType: 'application/json',
    ).saveTo(location.path);
    return true;
  }

  Future<CourseBackupData?> chooseBackup() async {
    final Uint8List? bytes;
    if (_isAndroid) {
      bytes = await _channel.invokeMethod<Uint8List>('open');
    } else {
      final file = await openFile(acceptedTypeGroups: _jsonTypes);
      if (file == null) return null;
      if (await file.length() > _maxBytes) throw _sizeError;
      bytes = await file.readAsBytes();
    }
    if (bytes == null) return null;
    if (bytes.isEmpty || bytes.length > _maxBytes) throw _sizeError;
    final String source;
    try {
      source = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('无法读取课表备份，请选择从本应用导出的 JSON 文件。');
    }
    return CourseBackupData.decode(source);
  }

  Future<void> restore(CourseBackupData backup) =>
      ImportedCourseStore.restoreBackup(backup);
}
