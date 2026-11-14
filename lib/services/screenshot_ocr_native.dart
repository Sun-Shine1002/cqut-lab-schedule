import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.cqutlabs.cqut_lab_schedule/screenshot_ocr');

Future<String> recognizeScreenshot(Uint8List bytes) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    throw const FormatException('此设备暂不支持截图识别，可以手动添加课程。');
  }
  return await _channel.invokeMethod<String>('recognize', bytes) ?? '';
}
