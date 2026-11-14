import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../theme/schedule_theme.dart';

Future<void> showCourseDetails(BuildContext context, Course course) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _CourseDetails(course: course),
  );
}

class _CourseDetails extends StatelessWidget {
  const _CourseDetails({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final isLab = course.kind == CourseKind.lab;
    final accent = isLab ? timetableLabInk : timetableRegularInk;
    final tint = isLab ? timetableLabFill : timetableRegularFill;
    final grade = course.grade?.trim();
    final details = <(IconData, String, String)>[
      (Icons.place_outlined, isLab ? '实验地点' : '上课地点', course.location),
      (Icons.person_outline_rounded, '任课教师', course.teacher),
      if (isLab)
        (
          Icons.assignment_outlined,
          '成绩',
          (grade == null || grade.isEmpty) ? '暂无成绩' : grade,
        ),
      if (isLab) (Icons.rate_review_outlined, '评教状态', course.evaluation),
    ];
    final weekday = weekdays[course.weekday - 1];
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: tint,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            isLab ? '实验课' : '正课',
                            style: TextStyle(
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        header: true,
                        child: Text(
                          course.name,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: '关闭详情',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: accent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${course.startTime}–${course.endTime}',
                            style: TextStyle(
                              color: accent,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '第 ${course.week} 周 · $weekday',
                            style: const TextStyle(color: scheduleMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 13),
            for (final (icon, label, value) in details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 19, color: scheduleMuted),
                    const SizedBox(width: 9),
                    Expanded(
                      flex: 2,
                      child: Text(
                        label,
                        style: const TextStyle(color: scheduleMuted),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Text(
                        value.isEmpty ? '—' : value,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
