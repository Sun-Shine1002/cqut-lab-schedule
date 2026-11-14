import 'package:cqut_lab_schedule/screens/schedule_screen.dart';
import 'package:cqut_lab_schedule/services/demo_regular_courses.dart';
import 'package:cqut_lab_schedule/services/schedule_parser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'opens the current week and highlights today even without a class',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            courses: demoRegularCourses(),
            now: () => DateTime(2026, 11, 14),
          ),
        ),
      );

      expect(find.text('第 11 周'), findsOneWidget);
      expect(find.text('11/09'), findsOneWidget);
      final today = find.text('11/14');
      expect(tester.widget<Text>(today).style?.color, Colors.black);
      expect(tester.widget<Text>(today).style?.fontWeight, FontWeight.w800);
      expect(find.bySemanticsLabel('今天，星期六，11月14日'), findsOneWidget);

      await tester.tap(find.byTooltip('上一周'));
      await tester.pumpAndSettle();
      expect(find.text('第 10 周'), findsOneWidget);
      expect(find.text('11/02'), findsOneWidget);
      expect(find.text('11/14'), findsNothing);
      expect(find.text('本周没有课程'), findsOneWidget);

      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('今天，星期六，11月14日'), findsOneWidget);
    },
  );

  testWidgets('switches weeks and filters courses by type on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = await rootBundle.loadString('assets/demo_schedule.html');
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          courses: demoRegularCourses(),
          demoLabs: ScheduleParser().parse(source).courses,
          isDemo: true,
          now: () => DateTime(2026, 9, 21),
        ),
      ),
    );
    expect(find.text('示例课表'), findsOneWidget);
    expect(find.text('中国近现代史纲要'), findsOneWidget);

    final overlap = find.byKey(const ValueKey('timetable-overlap-3-1'));
    await tester.ensureVisible(overlap);
    await tester.tap(overlap);
    await tester.pumpAndSettle();
    expect(find.text('查看重叠课程'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '扭摆法测物体转动惯量'));
    await tester.pumpAndSettle();
    expect(find.text('暂无成绩'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('上一周'));
    await tester.pumpAndSettle();
    expect(find.text('本周没有课程'), findsOneWidget);

    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    expect(find.text('双棱镜干涉'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '实验课'));
    await tester.pumpAndSettle();
    expect(find.text('中国近现代史纲要'), findsNothing);
    expect(find.text('扭摆法测物体转动惯量'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '第 4 周'));
    await tester.pumpAndSettle();
    final lastWeek = find.widgetWithText(ListTile, '第 7 周');
    await tester.scrollUntilVisible(
      lastWeek,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(lastWeek);
    await tester.pumpAndSettle();
    expect(find.text('光学综合实验'), findsOneWidget);
    expect(find.text('光栅衍射'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('光学综合实验')).dx,
      lessThan(tester.getTopLeft(find.text('光栅衍射')).dx),
    );
    expect(
      tester.getTopLeft(find.text('光栅衍射')).dy,
      lessThan(tester.getTopLeft(find.text('光学综合实验')).dy),
    );

    await tester.ensureVisible(find.text('光学综合实验'));
    await tester.tap(find.text('光学综合实验'));
    await tester.pumpAndSettle();
    expect(find.text('暂无成绩'), findsOneWidget);
    expect(find.text('未评教'), findsOneWidget);
    expect(find.text('明理楼211'), findsWidgets);
    await tester.tap(find.byTooltip('关闭详情'));
    await tester.pumpAndSettle();
    expect(find.text('暂无成绩'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
