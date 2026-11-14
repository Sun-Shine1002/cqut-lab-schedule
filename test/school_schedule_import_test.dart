import 'package:cqut_lab_schedule/models/course.dart';
import 'package:cqut_lab_schedule/screens/regular_schedule_import_screen.dart';
import 'package:cqut_lab_schedule/services/regular_schedule_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _schedule = '''{
  "courses": [{"name":"数据结构","teacher":"王老师","position":"弘远楼",
    "day":2,"startSection":1,"endSection":1,"weeks":[2,5]}],
  "timeSlots": [{"number":1,"startTime":"08:30","endTime":"09:15"}],
  "config": {"semesterStartDate":"2026-08-31","semesterTotalWeeks":21}
}''';

void main() {
  testWidgets(
    'school import previews before writing and can retry failed saves',
    (tester) async {
      RegularScheduleImport? saved;
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.of(context).push<RegularScheduleImport>(
                      MaterialPageRoute(
                        builder: (_) => RegularScheduleImportScreen(
                          readSchool: () async => _schedule,
                          saveCourses: (courses) async {
                            if (++attempts == 1)
                              throw const FormatException('本地保存失败');
                            saved = courses;
                          },
                        ),
                      ),
                    ),
                child: const Text('打开导入页'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开导入页'));
      await tester.pumpAndSettle();
      expect(find.text('课程导入功能参考 GitHub 开源项目“拾光课程表”。'), findsOneWidget);
      expect(find.text('选择 JSON 文件'), findsNothing);
      await tester.tap(find.text('从学校导入'));
      await tester.pumpAndSettle();
      expect(find.text('读取到 2 个上课安排'), findsOneWidget);
      expect(saved, isNull);

      await tester.tap(find.text('确认导入'));
      await tester.pumpAndSettle();
      expect(find.text('本地保存失败'), findsOneWidget);
      expect(find.text('读取到 2 个上课安排'), findsOneWidget);

      await tester.tap(find.text('确认导入'));
      await tester.pumpAndSettle();
      expect(find.text('打开导入页'), findsOneWidget);
      expect(saved!.courses.map((course) => (course.kind, course.week)), [
        (CourseKind.regular, 2),
        (CourseKind.regular, 5),
      ]);
      expect(saved!.calendar?.firstMonday, DateTime.utc(2026, 8, 31));
      expect(saved!.calendar?.totalWeeks, 21);
    },
  );
}
