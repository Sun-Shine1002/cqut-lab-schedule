import 'dart:async';
import 'dart:ui' as ui;

import 'package:cqut_lab_schedule/screens/lab_screenshot_import_screen.dart';
import 'package:cqut_lab_schedule/services/lab_screenshot_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('resizes the thumbnail and uses the original for zoom and OCR', (
    tester,
  ) async {
    final screenshot = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xffe7ebf0), ui.BlendMode.src);
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(1080, 6000);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          return png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
    }))!;
    Object? recognized;
    await tester.pumpWidget(
      MaterialApp(
        home: LabScreenshotImportScreen(
          pickScreenshot: () async => screenshot,
          recognizeScreenshot: (bytes) async {
            recognized = bytes;
            return const <LabCourseDraft>[];
          },
          saveCourses: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('选择截图'));
    await tester.pumpAndSettle();
    final images = find.byWidgetPredicate(
      (widget) => widget is Image && widget.semanticLabel == '实验课表截图',
    );
    final thumbnail = tester.widget<Image>(images).image as ResizeImage;
    expect(thumbnail.height, (176 * tester.view.devicePixelRatio).ceil());
    expect(thumbnail.policy, ResizeImagePolicy.fit);
    expect((thumbnail.imageProvider as MemoryImage).bytes, same(screenshot));
    final decodedSize = (await tester.runAsync(() async {
      final decoded = Completer<Size>();
      final stream = thumbnail.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (info, _) {
          if (!decoded.isCompleted) {
            decoded.complete(
              Size(info.image.width.toDouble(), info.image.height.toDouble()),
            );
          }
          info.dispose();
        },
        onError: (Object error, StackTrace? stack) {
          if (!decoded.isCompleted) decoded.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      try {
        return await decoded.future.timeout(const Duration(seconds: 10));
      } finally {
        stream.removeListener(listener);
      }
    }))!;
    expect(decodedSize.width, lessThanOrEqualTo(thumbnail.width!));
    expect(decodedSize.height, lessThanOrEqualTo(thumbnail.height!));
    expect(decodedSize.height, lessThan(6000));
    expect(decodedSize.aspectRatio, closeTo(1080 / 6000, 0.005));

    await tester.tap(images);
    await tester.pumpAndSettle();
    expect(find.text('截图预览'), findsOneWidget);
    final fullscreenImage = find.descendant(
      of: find.byType(Dialog),
      matching: images,
    );
    final preview = tester.widget<Image>(fullscreenImage).image as MemoryImage;
    expect(preview.bytes, same(screenshot));

    await tester.tap(find.byTooltip('关闭预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('识别截图'));
    await tester.pumpAndSettle();
    expect(recognized, same(screenshot));
  });
}
