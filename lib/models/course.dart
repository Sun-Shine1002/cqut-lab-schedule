enum CourseKind { regular, lab }

class Course {
  const Course({
    required this.name,
    required this.week,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.teacher,
    this.kind = CourseKind.lab,
    this.grade,
    this.evaluation = '',
  });

  final String name;
  final int week;
  final int weekday;
  final String startTime;
  final String endTime;
  final String location;
  final String teacher;
  final CourseKind kind;
  final String? grade;
  final String evaluation;
}
