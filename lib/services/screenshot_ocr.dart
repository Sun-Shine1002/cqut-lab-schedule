import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'screenshot_ocr_native.dart'
    if (dart.library.js_interop) 'screenshot_ocr_web.dart'
    as platform;

Future<Uint8List?> pickLabScreenshot() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: '截图',
        extensions: ['png', 'jpg', 'jpeg', 'webp'],
        mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
      ),
    ],
  );
  if (file == null) return null;
  final size = await file.length();
  if (size == 0 || size > 12 * 1024 * 1024) {
    throw const FormatException('请选择 12 MB 以内的有效截图。');
  }
  return file.readAsBytes();
}

Future<String> recognizeLabScreenshot(Uint8List bytes) =>
    platform.recognizeScreenshot(bytes);
