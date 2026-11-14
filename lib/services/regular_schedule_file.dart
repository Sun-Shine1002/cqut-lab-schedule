import 'dart:convert';

import 'package:file_selector/file_selector.dart';

Future<String?> pickRegularScheduleFile() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: '课表 JSON',
        extensions: ['json'],
        mimeTypes: ['application/json'],
      ),
    ],
  );
  if (file == null) return null;
  final size = await file.length();
  if (size == 0 || size > 2 * 1024 * 1024) {
    throw const FormatException('请选择 2 MB 以内的课表 JSON 文件。');
  }
  try {
    return utf8.decode(await file.readAsBytes());
  } on FormatException {
    throw const FormatException('文件编码无法读取，请重新导出课表 JSON。');
  }
}
