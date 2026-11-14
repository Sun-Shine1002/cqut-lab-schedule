import 'package:cqut_lab_schedule/models/course.dart';
import 'package:cqut_lab_schedule/widgets/timetable_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'shows classroom building and full code in a narrow one-period card',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const lecture = Course(
        name: '中国近现代史纲要',
        week: 11,
        weekday: 1,
        startTime: '08:30',
        endTime: '09:15',
        location: '两江校区 弘远楼B0119',
        teacher: '',
        kind: CourseKind.regular,
      );
      const sport = Course(
        name: '大学体育',
        week: 11,
        weekday: 2,
        startTime: '08:30',
        endTime: '10:10',
        location: '两江校区 两江操场1号',
        teacher: '',
        kind: CourseKind.regular,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TimetableGrid(
                courses: const [lecture, sport],
                onCourseTap: (_) {},
              ),
            ),
          ),
        ),
      );

      final lectureCard = find.byKey(const ValueKey(lecture));
      final code = find.descendant(
        of: lectureCard,
        matching: find.text('B0119'),
      );
      expect(code, findsOneWidget);
      expect(
        find.descendant(of: lectureCard, matching: find.text('弘远楼')),
        findsOneWidget,
      );
      expect(tester.widget<Text>(code).overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester.getBottomRight(code).dy,
        lessThanOrEqualTo(tester.getBottomRight(lectureCard).dy),
      );
      expect(find.text('两江操场'), findsOneWidget);
      expect(find.text('1号'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
