import 'package:cqut_lab_schedule/models/course.dart';
import 'package:cqut_lab_schedule/models/term_calendar.dart';
import 'package:cqut_lab_schedule/screens/course_document_import_screen.dart';
import 'package:cqut_lab_schedule/services/course_document_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'selects a class and saves only the checked experiment sessions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(410, 960);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final regular = _course('大学物理', '18:00', kind: CourseKind.regular);
      final firstOptics = [
        _course('光学实验', '09:00'),
        _course('光学实验', '09:00', week: 3),
      ];
      final secondOptics = [_course('光学实验', '13:00', week: 2)];
      final firstElectrical = [_course('电学实验', '15:00')];
      final classes = {
        '01 班': CourseDocumentClass(
          courses: [regular],
          alternatives: [
            [firstOptics, secondOptics],
            [
              firstElectrical,
              [_course('电学实验', '17:00', week: 2)],
            ],
          ],
        ),
        '02 班': CourseDocumentClass(courses: [_course('力学实验', '09:00')]),
      };
      List<Course>? saved;
      List<Course>? returned;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('打开导入'),
                onPressed: () async {
                  returned = await Navigator.push<List<Course>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CourseDocumentImportScreen(
                        readFile: () async => classes,
                        saveCourses: (courses) async => saved = courses,
                        termCalendar: TermCalendar(DateTime(2026, 9, 7)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择 Excel 或 Word 文件'));
      await tester.pumpAndSettle();
      expect(find.text('课程预览'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('01 班').last);
      await tester.pumpAndSettle();
      expect(find.text('课程预览'), findsOneWidget);
      expect(find.text('还有 2 组实验待选择时段'), findsOneWidget);
      expect(find.textContaining('9 月 7 日 · 星期一 · 09:00'), findsOneWidget);
      expect(find.textContaining('9 月 21 日 · 星期一 · 09:00'), findsOneWidget);
      expect(find.text('第 1、3 周'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(4));
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == false),
        isTrue,
      );

      for (final time in ['09:00', '13:00', '15:00']) {
        final choice = find.ancestor(
          of: find.textContaining('$time–19:00'),
          matching: find.byType(CheckboxListTile),
        );
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        if (time == '13:00') {
          expect(find.text('还有 1 组实验待选择时段'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '确认导入 4 条课程'),
                )
                .onPressed,
            isNull,
          );
        }
      }

      expect(saved, isNull);
      await tester.tap(find.text('确认导入 5 条课程'));
      await tester.pumpAndSettle();
      expect(saved, [
        firstOptics[0],
        firstElectrical.single,
        regular,
        secondOptics.single,
        firstOptics[1],
      ]);
      expect(returned, saved);
    },
  );
}

Course _course(
  String name,
  String start, {
  int week = 1,
  CourseKind kind = CourseKind.lab,
}) => Course(
  name: name,
  week: week,
  weekday: DateTime.monday,
  startTime: start,
  endTime: '19:00',
  location: '实验楼 201',
  teacher: '',
  kind: kind,
);
