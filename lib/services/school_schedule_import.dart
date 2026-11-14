import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.cqutlabs.cqut_lab_schedule/regular_import');

bool get supportsSchoolScheduleImport =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<String?> importSchoolSchedule() async {
  final reader = await rootBundle.loadString('assets/cqut_regular_import.js');
  return _channel.invokeMethod<String>('open', reader);
}
