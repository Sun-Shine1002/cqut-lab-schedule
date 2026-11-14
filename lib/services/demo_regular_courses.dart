import '../models/course.dart';

List<Course> demoRegularCourses() {
  const slots = [
    ('中国近现代史纲要', 1, '08:30', '10:10', '弘远楼 B0119'),
    ('大学体育', 2, '10:30', '12:10', '两江操场'),
    ('数字电子技术', 2, '16:20', '18:00', '弘远楼 B0212'),
    ('大学物理Ⅱ', 3, '10:30', '12:10', '弘远楼 B0302'),
    ('数字电子技术', 3, '16:20', '18:00', '弘远楼 B0212'),
    ('线性代数[理工]', 3, '19:00', '20:35', '弘远楼 C0118'),
    ('大学英语', 4, '08:30', '10:10', '弘远楼 A0201'),
    ('大学物理Ⅱ', 4, '10:30', '12:10', '弘远楼 B0302'),
    ('数字电子技术', 4, '19:00', '20:35', '弘远楼 B0417'),
    ('线性代数', 5, '10:30', '12:10', '弘远楼 C0118'),
    ('社会主义发展史', 5, '19:00', '20:35', '弘远楼 B0408'),
  ];

  return [
    for (final week in [4, 5, 6, 7, 11])
      for (final (name, weekday, start, end, location) in slots)
        Course(
          name: name,
          week: week,
          weekday: weekday,
          startTime: start,
          endTime: end,
          location: location,
          teacher: '',
          kind: CourseKind.regular,
        ),
  ];
}
