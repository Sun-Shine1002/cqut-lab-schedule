import 'dart:js_interop';
import 'dart:typed_data';

@JS('cqutRecognizeLabScreenshot')
external JSPromise<_RecognitionResult> _recognizeScreenshot(JSUint8Array bytes);

extension type _RecognitionResult(JSObject _) implements JSObject {
  external JSString? get text;
  external JSString? get error;
}

Future<String> recognizeScreenshot(Uint8List bytes) async {
  final result = await _recognizeScreenshot(bytes.toJS).toDart;
  if (result.error case final error?) {
    throw FormatException(error.toDart);
  }
  return result.text?.toDart ?? '';
}
