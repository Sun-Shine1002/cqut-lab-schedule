import 'package:cqut_lab_schedule/models/course.dart';
import 'package:cqut_lab_schedule/services/course_document_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'preserves project choices across weeks and keeps each source row together',
    () {
      const daytime = [
        '电工实验',
        '',
        '组合逻辑',
        '',
        '第9、10周',
        '二',
        '8：30--10：00',
        'A班、B班',
        '',
        '指导老师',
        '实验楼215',
      ];
      final groups = parseCourseDocumentTables({
        '课内实验': [
          ['实验课程安排表'],
          [
            '课 程 名 称',
            '实验总学时',
            '实 验 项 目',
            '实验',
            '开课',
            '星 期',
            '节 次',
            '专业班级',
            '人数',
            '指导教师',
            '实验室房间',
          ],
          [
            '课 程 名 称',
            '实验总学时',
            '实 验 项 目',
            '学时',
            '周次',
            '星 期',
            '节 次',
            '专业班级',
            '人数',
            '指导教师',
            '实验室房间',
          ],
          daytime,
          [...daytime]
            ..[4] = '第12周'
            ..[6] = '18：00-21：00',
          [...daytime]..[4] = '第10、9、9周',
          [...daytime]..[2] = '另一项目',
          [...daytime]..[4] = '待定',
        ],
      });

      expect(groups.keys, unorderedEquals(['A班', 'B班']));
      for (final schedule in groups.values) {
        expect(schedule.courses.map((course) => (course.name, course.week)), [
          ('电工实验 · 另一项目', 9),
          ('电工实验 · 另一项目', 10),
        ]);
        final options = schedule.alternatives.single;
        expect(
          options.map(
            (row) => row
                .map(
                  (course) => (course.week, course.startTime, course.endTime),
                )
                .toList(),
          ),
          [
            [(9, '08:30', '10:00'), (10, '08:30', '10:00')],
            [(12, '18:00', '21:00')],
          ],
        );
        final courses = options.expand((row) => row);
        expect(
          courses.every((course) => course.kind == CourseKind.lab),
          isTrue,
        );
        final course = courses.first;
        expect(course.name, '电工实验 · 组合逻辑');
        expect(course.week, 9);
        expect(course.weekday, 2);
        expect(course.teacher, '指导老师');
        expect(course.location, '实验楼215');
      }
    },
  );

  test('reads explicit times, week selections and Liangjiang periods', () {
    final groups = parseCourseDocumentTables({
      'Table 1': [
        ['班级：A班'],
        ['课名', '教学周', '周几', '开始时间', '结束时间', '教师'],
        ['高等数学', '第1-6周（单周）\n第8周', '周一', '0.35416666666667', '9:15', ''],
      ],
      'Table 2': [
        ['班级', '课程', '周次', '上课星期', '上课节次', '地点'],
        ['B班', '大学英语', '第7周', '星期五', '第3至4节', '教室 207'],
        ['B班', '节次不明', '第7周', '星期五', '第10至12节', ''],
      ],
    });

    final mathCourses = groups['A班']!.courses;
    expect(mathCourses.map((course) => course.week), [1, 3, 5, 8]);
    expect(
      mathCourses.every((course) => course.kind == CourseKind.regular),
      isTrue,
    );
    expect(mathCourses.first.startTime, '08:30');
    final englishCourse = groups['B班']!.courses.single;
    expect(englishCourse.startTime, '10:30');
    expect(englishCourse.endTime, '12:10');
  });

  test(
    'only retains rows with an explicit class, valid date and usable times',
    () {
      final groups = parseCourseDocumentTables({
        '未分班': [
          ['实验名称', '周次', '星期', '上课时间'],
          ['未分班实验', '4', '四', '8:30-10:00'],
        ],
        '分班': [
          ['班级', '实验名称', '周次', '星期', '上课时间'],
          ['A班', '错误周次', '0', '四', '8:30-10:00'],
          ['A班', '错误星期', '4', '八', '8:30-10:00'],
          ['A班', '错误时间', '4', '四', '8:30-08:00'],
          ['A班', '湿化学实验', '4', '四', '8:30-10:00'],
        ],
      });

      expect(groups.keys, ['A班']);
      expect(groups['A班']!.courses.single.kind, CourseKind.lab);
      expect(groups['A班']!.courses.single.name, '湿化学实验');
      expect(groups['A班']!.alternatives, isEmpty);
    },
  );
}
