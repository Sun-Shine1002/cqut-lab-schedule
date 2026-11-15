import 'package:cqut_lab_schedule/models/course.dart';
import 'package:cqut_lab_schedule/models/term_calendar.dart';
import 'package:cqut_lab_schedule/screens/schedule_screen.dart';
import 'package:cqut_lab_schedule/services/demo_regular_courses.dart';
import 'package:cqut_lab_schedule/services/schedule_parser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('chooses both lab import methods and saves the direct preview', (
    tester,
  ) async {
    const lab = Course(
      name: '液体黏度测量',
      week: 2,
      weekday: DateTime.monday,
      startTime: '08:30',
      endTime: '10:10',
      location: '实验楼 201',
      teacher: '',
    );
    List<Course>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          courses: const [],
          termCalendar: TermCalendar(DateTime(2026, 9, 7), totalWeeks: 3),
          now: () => DateTime(2026, 9, 7),
          readSchoolLabs: () async => const [lab],
          saveLabs: (courses) async => saved = courses,
        ),
      ),
    );

    final importButton = find.byTooltip('导入实验课');
    await tester.tap(importButton);
    await tester.pumpAndSettle();
    expect(find.text('请先连接校园网，点击跳转登录实验选课系统。'), findsOneWidget);

    await tester.tap(find.text('截图导入'));
    await tester.pumpAndSettle();
    expect(find.text('截图导入实验课'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(importButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('直接导入'));
    await tester.pumpAndSettle();
    expect(find.text('液体黏度测量'), findsOneWidget);
    expect(saved, isNull);

    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();
    expect(saved, [lab]);
    expect(find.text('第 2 周'), findsOneWidget);
    expect(find.text('液体黏度测量'), findsOneWidget);
  });

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
      expect(find.text('本周没有课程'), findsNothing);
      expect(find.text('08:30'), findsWidgets);

      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('今天，星期六，11月14日'), findsOneWidget);
    },
  );

  testWidgets(
    'drags whole weeks into view, snaps into place, and still scrolls vertically',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 620);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            courses: const [
              Course(
                name: '课表手势测试',
                week: 2,
                weekday: DateTime.monday,
                startTime: '08:30',
                endTime: '10:10',
                location: '弘远楼 B0119',
                teacher: '',
                kind: CourseKind.regular,
              ),
            ],
            termCalendar: TermCalendar(DateTime(2026, 9, 7), totalWeeks: 3),
            now: () => DateTime(2026, 9, 14),
          ),
        ),
      );

      const currentDate = '今天，星期一，9月14日';
      final pages = find.byKey(const ValueKey('timetable-week-swipe'));
      final grid = find.byKey(const PageStorageKey(('timetable-scroll', 2)));
      expect(find.text('第 2 周'), findsOneWidget);
      expect(find.bySemanticsLabel(currentDate), findsOneWidget);

      final position = tester
          .state<ScrollableState>(
            find.descendant(of: grid, matching: find.byType(Scrollable)),
          )
          .position;
      await tester.drag(grid, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(find.text('第 2 周'), findsOneWidget);
      position.jumpTo(0);
      await tester.pumpAndSettle();

      await tester.tap(find.text('课表手势测试'));
      await tester.pumpAndSettle();
      expect(find.text('上课地点'), findsOneWidget);
      expect(find.text('弘远楼 B0119'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pumpAndSettle();

      final restingLeft = tester.getTopLeft(grid).dx;
      final viewport = tester.getRect(pages);
      final nextGrid = find.byKey(
        const PageStorageKey(('timetable-scroll', 3)),
      );
      final touch = await tester.startGesture(viewport.center);
      await touch.moveBy(
        const Offset(-26, 0),
        timeStamp: const Duration(milliseconds: 100),
      );
      await touch.moveBy(
        const Offset(-100, 0),
        timeStamp: const Duration(milliseconds: 250),
      );
      await tester.pump();
      expect(tester.getTopLeft(grid).dx, lessThan(restingLeft - 50));
      expect(tester.getTopLeft(nextGrid).dx, lessThan(viewport.right - 50));
      expect(find.text('09/21'), findsOneWidget);
      await touch.up(timeStamp: const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      expect(tester.getTopLeft(grid).dx, closeTo(restingLeft, .5));

      for (final (dx, expectedWeek) in [
        (-230.0, 3),
        (-230.0, 3),
        (230.0, 2),
        (230.0, 1),
        (230.0, 1),
        (-230.0, 2),
      ]) {
        await tester.drag(pages, Offset(dx, 0));
        await tester.pumpAndSettle();
        expect(find.text('第 $expectedWeek 周'), findsOneWidget);
        expect(
          find.bySemanticsLabel(currentDate),
          expectedWeek == 2 ? findsOneWidget : findsNothing,
        );
      }
      expect(find.text('课表手势测试'), findsOneWidget);
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
    expect(find.text('本周没有课程'), findsNothing);

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
