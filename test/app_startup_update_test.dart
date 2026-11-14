import 'dart:async';

import 'package:cqut_lab_schedule/screens/schedule_screen.dart';
import 'package:cqut_lab_schedule/services/app_update.dart';
import 'package:cqut_lab_schedule/services/demo_regular_courses.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final release = AppRelease(
    versionName: '0.3.0',
    versionCode: 4,
    notes: '新版课表',
    apkUrl: Uri.https('example.org', '/cqut-schedule.apk'),
    sha256: 'a' * 64,
  );

  Widget app(Future<AppRelease?> Function() check) => MaterialApp(
    home: ScheduleScreen(
      courses: demoRegularCourses(),
      now: () => DateTime(2026, 11, 14),
      checkForUpdate: check,
    ),
  );

  testWidgets(
    'keeps the timetable usable while checking, then offers updates',
    (tester) async {
      final pending = Completer<AppRelease?>();
      var checks = 0;
      await tester.pumpWidget(
        app(() {
          checks++;
          return pending.future;
        }),
      );

      expect(checks, 1);
      expect(find.text('第 11 周'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(find.byTooltip('上一周'));
      await tester.pumpAndSettle();
      expect(find.text('第 10 周'), findsOneWidget);
      expect(checks, 1);

      pending.complete(release);
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.textContaining('0.3.0'), findsOneWidget);
      expect(find.text('查看更新'), findsOneWidget);

      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('第 10 周'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(checks, 1);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('waits until the user closes course details before prompting', (
    tester,
  ) async {
    final pending = Completer<AppRelease?>();
    await tester.pumpWidget(app(() => pending.future));

    await tester.tap(find.text('中国近现代史纲要'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭详情'), findsOneWidget);

    pending.complete(release);
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭详情'), findsOneWidget);
    expect(find.text('发现新版本'), findsNothing);

    await tester.tap(find.byTooltip('关闭详情'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭详情'), findsNothing);
    expect(find.text('发现新版本'), findsOneWidget);
  });

  testWidgets('stays quiet when the current release is latest', (tester) async {
    await tester.pumpWidget(app(() async => null));
    await tester.pumpAndSettle();

    expect(find.text('第 11 周'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('stays quiet when the background check times out', (
    tester,
  ) async {
    await tester.pumpWidget(app(() async => throw TimeoutException('offline')));
    await tester.pumpAndSettle();

    expect(find.text('第 11 周'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
