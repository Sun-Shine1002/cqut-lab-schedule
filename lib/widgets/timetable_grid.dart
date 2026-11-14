import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../theme/schedule_theme.dart';

const _railWidth = 37.0;
const _periodHeight = 53.0;
const _minutesOutsideScale = .55;
const _minimumBlockHeight = 18.0;
const _todayFill = Color(0xFFF3EDF7);
const _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];
final _campusPrefix = RegExp(r'^(?:两江|花溪|杨家坪)校区[\s，、,·-]*(?=\S)');
final _buildingAndRoom = RegExp(
  r'^(.*?(?:楼|馆|操场|实验室|教室))[\s·]*([A-Za-z]*\s*[0-9０-９][A-Za-z0-9０-９-]*(?:号|室)?)$',
);

// The reference timetable shows periods 1–10. Experimental times are mapped
// onto the clock even when they begin or end outside those periods.
const _periods = <(int, int)>[
  (510, 555), // 08:30–09:15
  (565, 610), // 09:25–10:10
  (630, 675), // 10:30–11:15
  (685, 730), // 11:25–12:10
  (860, 905), // 14:20–15:05
  (915, 960), // 15:15–16:00
  (980, 1025), // 16:20–17:05
  (1035, 1080), // 17:15–18:00
  (1140, 1185), // 19:00–19:45
  (1190, 1235), // 19:50–20:35
];

class TimetableWeekdayHeader extends StatelessWidget {
  const TimetableWeekdayHeader({
    super.key,
    required this.weekStart,
    required this.today,
  });

  final DateTime weekStart;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F5F8),
        border: Border(bottom: BorderSide(color: scheduleLine)),
      ),
      child: SizedBox(
        height: 46,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _railWidth,
              child: Semantics(
                container: true,
                label: '${weekStart.month}月',
                excludeSemantics: true,
                child: _CalendarHeading(
                  upper: '${weekStart.month}',
                  lower: '月',
                  emphasized: true,
                ),
              ),
            ),
            for (final (dayIndex, day) in _dayLabels.indexed)
              Expanded(child: _dayHeading(dayIndex, day)),
          ],
        ),
      ),
    );
  }

  Widget _dayHeading(int dayIndex, String day) {
    final date = DateTime.utc(
      weekStart.year,
      weekStart.month,
      weekStart.day + dayIndex,
    );
    final isToday = DateUtils.isSameDay(date, today);
    final month = date.month.toString().padLeft(2, '0');
    final dayOfMonth = date.day.toString().padLeft(2, '0');
    return Semantics(
      container: true,
      label:
          '${isToday ? '今天，' : ''}${weekdays[dayIndex]}，${date.month}月${date.day}日',
      excludeSemantics: true,
      child: ColoredBox(
        color: isToday ? _todayFill : Colors.transparent,
        child: _CalendarHeading(
          upper: day,
          lower: '$month/$dayOfMonth',
          emphasized: isToday,
        ),
      ),
    );
  }
}

class _CalendarHeading extends StatelessWidget {
  const _CalendarHeading({
    required this.upper,
    required this.lower,
    required this.emphasized,
  });

  final String upper;
  final String lower;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: emphasized ? Colors.black : scheduleMuted,
      fontWeight: emphasized ? FontWeight.w800 : FontWeight.w400,
      fontSize: 12,
      height: 1.15,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(upper, style: style.copyWith(fontSize: 15)),
            const SizedBox(height: 2),
            Text(lower, style: style),
          ],
        ),
      ),
    );
  }
}

class TimetableGrid extends StatelessWidget {
  const TimetableGrid({
    super.key,
    required this.courses,
    required this.onCourseTap,
    this.todayWeekday,
  });

  final List<Course> courses;
  final ValueChanged<Course> onCourseTap;
  final int? todayWeekday;

  Future<void> _openOverlap(BuildContext context, List<Course> courses) async {
    final course = await showModalBottomSheet<Course>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  '查看重叠课程',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final course in courses)
                ListTile(
                  key: ValueKey(course),
                  leading: Icon(
                    course.kind == CourseKind.lab
                        ? Icons.science_outlined
                        : Icons.menu_book_outlined,
                    color: course.kind == CourseKind.lab
                        ? timetableLabInk
                        : timetableRegularInk,
                  ),
                  title: Text(course.name),
                  subtitle: Text('${course.startTime}–${course.endTime}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, course),
                ),
            ],
          ),
        ),
      ),
    );
    if (context.mounted && course != null) {
      onCourseTap(course);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timedCourses = [for (final course in courses) _TimedCourse(course)];
    final scale = _ClockScale(timedCourses);
    final positions = [
      for (final (start, end) in _periods)
        (scale.offsetOf(start), scale.offsetOf(end)),
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFFFCFA)),
      child: SizedBox(
        height: scale.height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _railWidth,
              child: Stack(
                children: [
                  if (scale.start < _periods.first.$1)
                    Positioned(
                      top: 2,
                      left: 0,
                      right: 0,
                      child: _ClockLabel(minutes: scale.start),
                    ),
                  for (final (index, (start, end)) in _periods.indexed)
                    Positioned(
                      top: positions[index].$1,
                      height: _periodHeight,
                      left: 0,
                      right: 0,
                      child: _PeriodLabel(
                        number: index + 1,
                        start: start,
                        end: end,
                      ),
                    ),
                  if (scale.end > _periods.last.$2)
                    Positioned(
                      bottom: 2,
                      left: 0,
                      right: 0,
                      child: _ClockLabel(minutes: scale.end),
                    ),
                ],
              ),
            ),
            for (var weekday = 1; weekday <= 7; weekday++)
              Expanded(
                child: _DayColumn(
                  weekday: weekday,
                  isToday: weekday == todayWeekday,
                  positions: positions,
                  blocks: _blocksFor(weekday, timedCourses, scale),
                  onCourseTap: onCourseTap,
                  onOverlapTap: (courses) => _openOverlap(context, courses),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.weekday,
    required this.isToday,
    required this.positions,
    required this.blocks,
    required this.onCourseTap,
    required this.onOverlapTap,
  });

  final int weekday;
  final bool isToday;
  final List<(double, double)> positions;
  final List<_CourseBlock> blocks;
  final ValueChanged<Course> onCourseTap;
  final ValueChanged<List<Course>> onOverlapTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isToday
            ? _todayFill
            : weekday < 6
            ? const Color(0xFFFEFCFA)
            : const Color(0xFFF8F5F9),
        border: const Border(left: BorderSide(color: scheduleLine)),
      ),
      child: Stack(
        children: [
          for (final (top, bottom) in positions)
            Positioned(
              top: top,
              height: bottom - top,
              left: 0,
              right: 0,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: scheduleLine)),
                ),
              ),
            ),
          for (final (index, block) in blocks.indexed)
            Positioned(
              top: block.top + 1,
              height: block.bottom - block.top - 2,
              left: 1,
              right: 1,
              child: _CourseTile(
                key: block.courses.length == 1
                    ? ValueKey(block.courses.single)
                    : ValueKey('timetable-overlap-$weekday-$index'),
                courses: block.courses,
                onTap: block.courses.length == 1
                    ? () => onCourseTap(block.courses.single)
                    : () => onOverlapTap(block.courses),
              ),
            ),
        ],
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({super.key, required this.courses, required this.onTap});

  final List<Course> courses;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final course = courses.first;
    final isLab = course.kind == CourseKind.lab;
    final ink = isLab ? timetableLabInk : timetableRegularInk;
    final hasOverlap = courses.length > 1;
    final mixedKinds =
        hasOverlap && courses.any((other) => other.kind != course.kind);
    final location = course.location.trim();
    final tileLocation = location.replaceFirst(_campusPrefix, '');
    final classroom = _buildingAndRoom.firstMatch(tileLocation);
    final label = [
      if (hasOverlap) '查看重叠课程，共 ${courses.length} 门',
      isLab ? '实验课' : '正课',
      course.name,
      '${course.startTime}至${course.endTime}',
      if (location.isNotEmpty) location,
    ].join('，');
    final titleStyle = TextStyle(
      color: ink,
      fontSize: 11.5,
      height: 1.2,
      fontWeight: FontWeight.w700,
    );
    final roomStyle = TextStyle(
      color: ink,
      fontSize: 11,
      height: 1.15,
      fontWeight: FontWeight.w600,
    );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: isLab ? timetableLabFill : timetableRegularFill,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(color: ink.withValues(alpha: .12)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (mixedKinds)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: 3,
                  child: ColoredBox(
                    color: isLab ? timetableRegularInk : timetableLabInk,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scaler = MediaQuery.textScalerOf(context);
                    final titleLine = scaler.scale(11.5) * 1.2;
                    final roomLine = scaler.scale(11) * 1.15;
                    final height = constraints.maxHeight;
                    final showLocation = tileLocation.isNotEmpty;
                    final showTitle =
                        !showLocation || height >= titleLine + roomLine + 2;
                    final showCount =
                        hasOverlap &&
                        height >=
                            titleLine * 2 + (showLocation ? roomLine + 2 : 0);
                    final roomLines =
                        height >=
                            titleLine * (showCount ? 2 : 1) + roomLine * 2 + 2
                        ? 2
                        : 1;
                    final titleLines = math.max(
                      1,
                      ((height -
                                  (showLocation
                                      ? roomLine * roomLines + 2
                                      : 0) -
                                  (showCount ? titleLine : 0)) /
                              titleLine)
                          .floor(),
                    );
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (showCount)
                          SizedBox(
                            height: titleLine,
                            child: _TileLine(
                              '+${courses.length - 1}',
                              style: titleStyle,
                            ),
                          ),
                        if (showTitle)
                          Flexible(
                            child: Text(
                              course.name,
                              maxLines: titleLines,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: titleStyle,
                            ),
                          ),
                        if (showLocation) ...[
                          if (showTitle) const SizedBox(height: 2),
                          if (classroom != null) ...[
                            if (roomLines == 2)
                              SizedBox(
                                height: roomLine,
                                child: _TileLine(
                                  classroom[1]!,
                                  style: roomStyle,
                                ),
                              ),
                            SizedBox(
                              height: math.min(height, roomLine),
                              child: _TileLine(
                                classroom[2]!.trim(),
                                style: roomStyle,
                              ),
                            ),
                          ] else
                            SizedBox(
                              height: math.min(height, roomLine * roomLines),
                              child: Center(
                                child: Text(
                                  tileLocation,
                                  maxLines: roomLines,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: roomStyle,
                                ),
                              ),
                            ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileLine extends StatelessWidget {
  const _TileLine(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, style: style, maxLines: 1, softWrap: false),
  );
}

class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel({
    required this.number,
    required this.start,
    required this.end,
  });

  final int number;
  final int start;
  final int end;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$number',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            _ClockLabel(minutes: start),
            _ClockLabel(minutes: end),
          ],
        ),
      ),
    );
  }
}

class _ClockLabel extends StatelessWidget {
  const _ClockLabel({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '$hour:$minute',
        style: const TextStyle(color: scheduleMuted, fontSize: 9, height: 1.3),
      ),
    );
  }
}

int _minutes(String clock) {
  final parts = clock.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

class _TimedCourse {
  _TimedCourse(this.course)
    : start = _minutes(course.startTime),
      end = _minutes(course.endTime);

  final Course course;
  final int start;
  final int end;
}

class _ClockScale {
  _ClockScale(List<_TimedCourse> courses)
    : start = courses.fold(
        _periods.first.$1,
        (earliest, course) => math.min(earliest, course.start),
      ),
      end = courses.fold(
        _periods.last.$2,
        (latest, course) => math.max(latest, course.end),
      );

  final int start;
  final int end;

  double get height => offsetOf(end) + _minimumBlockHeight;

  double offsetOf(int time) {
    var previousEnd = start;
    var offset = 0.0;
    for (final (periodStart, periodEnd) in _periods) {
      final gap = periodStart - previousEnd;
      final gapHeight = switch (gap) {
        0 => 0.0,
        <= 10 => 3.0,
        <= 20 => 5.0,
        _ when previousEnd == start => math.max(14, gap * _minutesOutsideScale),
        _ => 9.0,
      };
      if (gap > 0 && time < periodStart) {
        return offset + gapHeight * (time - previousEnd) / gap;
      }
      offset += gapHeight;
      if (time <= periodEnd) {
        return offset +
            _periodHeight * (time - periodStart) / (periodEnd - periodStart);
      }
      offset += _periodHeight;
      previousEnd = periodEnd;
    }
    return offset + (time - previousEnd) * _minutesOutsideScale;
  }
}

class _CourseBlock {
  _CourseBlock(this.top, this.bottom, this.courses);

  final double top;
  double bottom;
  final List<Course> courses;
}

List<_CourseBlock> _blocksFor(
  int weekday,
  List<_TimedCourse> courses,
  _ClockScale scale,
) {
  final day =
      courses.where((course) => course.course.weekday == weekday).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final blocks = <_CourseBlock>[];
  for (final course in day) {
    final top = scale.offsetOf(course.start);
    final bottom = math.max(
      top + _minimumBlockHeight,
      scale.offsetOf(course.end),
    );
    if (blocks.isNotEmpty && top < blocks.last.bottom) {
      final block = blocks.last;
      block.bottom = math.max(block.bottom, bottom);
      block.courses.add(course.course);
    } else {
      blocks.add(_CourseBlock(top, bottom, [course.course]));
    }
  }
  return blocks;
}
