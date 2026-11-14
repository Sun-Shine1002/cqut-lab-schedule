import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/term_calendar.dart';
import '../services/app_update.dart';
import '../services/course_backup_service.dart';
import '../services/lab_screenshot_parser.dart';
import '../services/regular_schedule_parser.dart';
import '../services/school_schedule_import.dart';
import '../services/screenshot_ocr.dart';
import '../theme/schedule_theme.dart';
import '../widgets/course_card.dart';
import '../widgets/timetable_grid.dart';
import 'app_update_screen.dart';
import 'course_backup_screen.dart';
import 'lab_screenshot_import_screen.dart';
import 'regular_schedule_import_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.courses,
    this.demoLabs = const [],
    this.importedLabs = const [],
    this.importedRegular = const [],
    this.saveLabs,
    this.saveRegular,
    this.backup,
    this.isDemo = false,
    this.termCalendar,
    this.now,
    this.checkForUpdate,
  });

  final List<Course> courses;
  final List<Course> demoLabs;
  final List<Course> importedLabs;
  final List<Course> importedRegular;
  final Future<List<Course>> Function(List<Course>)? saveLabs;
  final Future<void> Function(RegularScheduleImport)? saveRegular;
  final CourseBackupService? backup;
  final bool isDemo;
  final TermCalendar? termCalendar;
  final DateTime Function()? now;
  final Future<AppRelease?> Function()? checkForUpdate;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with WidgetsBindingObserver {
  int? _selectedWeek;
  late TermCalendar _calendar;
  late DateTime _today;
  late List<Course> _importedLabs;
  late List<Course> _importedRegular;
  CourseKind? _kind;
  AppRelease? _availableUpdate;
  bool _startupCheckStarted = false;
  bool _offerUpdate = false;
  bool _updateScreenOpen = false;
  double _weekSwipeDistance = 0;

  bool get _canCheckForUpdate =>
      widget.checkForUpdate != null ||
      (AppUpdate.supported && AppUpdate.configured);

  Iterable<Course> get _courses => [
    ...(_importedRegular.isEmpty ? widget.courses : _importedRegular),
    ...(_importedLabs.isNotEmpty
        ? _importedLabs
        : _importedRegular.isEmpty
        ? widget.demoLabs
        : const []),
  ];

  int get _lastWeek => _courses.fold(
    _calendar.totalWeeks ?? 1,
    (last, course) => course.week > last ? course.week : last,
  );

  int get _week =>
      _selectedWeek ?? _calendar.weekOf(_today).clamp(1, _lastWeek);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _importedLabs = widget.importedLabs;
    _importedRegular = widget.importedRegular;
    _calendar = widget.termCalendar ?? TermCalendar.cqutFall2026;
    _today = (widget.now ?? DateTime.now)();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkForUpdate());
    });
  }

  Future<void> _checkForUpdate() async {
    if (!_canCheckForUpdate || _startupCheckStarted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _startupCheckStarted = true;
    try {
      final check = widget.checkForUpdate;
      final update = check == null
          ? await AppUpdate.check(await AppUpdate.info())
          : await check();
      if (mounted && update != null) {
        setState(() {
          _availableUpdate = update;
          _offerUpdate = !_updateScreenOpen;
        });
      }
    } on Exception {
      // The manual check reports connection errors.
    }
  }

  Future<void> _promptForUpdate(AppRelease release) async {
    if (!mounted ||
        !_offerUpdate ||
        release != _availableUpdate ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _offerUpdate = false;
    final ready = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('课程表 ${release.versionName} 已发布。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('查看更新'),
          ),
        ],
      ),
    );
    if (mounted && ready == true) await _openUpdate();
  }

  Future<void> _openBackup(CourseBackupService backup) async {
    final restored = await Navigator.of(context).push<CourseBackupData>(
      MaterialPageRoute(builder: (_) => CourseBackupScreen(backup: backup)),
    );
    if (!mounted || restored == null) return;
    setState(() {
      _importedLabs = restored.labCourses;
      _importedRegular = restored.regularCourses;
      _calendar = restored.termCalendar ?? TermCalendar.cqutFall2026;
      _selectedWeek = null;
      _kind = null;
    });
  }

  Future<void> _openUpdate() async {
    _offerUpdate = false;
    _updateScreenOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AppUpdateScreen(available: _availableUpdate),
        ),
      );
    } finally {
      _updateScreenOpen = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final today = (widget.now ?? DateTime.now)();
    if (!DateUtils.isSameDay(_today, today)) {
      setState(() => _today = today);
    }
    if (!_startupCheckStarted) unawaited(_checkForUpdate());
    final update = _availableUpdate;
    if (_offerUpdate && update != null) {
      unawaited(_promptForUpdate(update));
    }
  }

  @override
  void didUpdateWidget(ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.importedLabs != oldWidget.importedLabs) {
      _importedLabs = widget.importedLabs;
    }
    if (widget.importedRegular != oldWidget.importedRegular) {
      _importedRegular = widget.importedRegular;
    }
    if (widget.termCalendar != oldWidget.termCalendar) {
      _calendar = widget.termCalendar ?? TermCalendar.cqutFall2026;
      _selectedWeek = null;
    }
    if (_week > _lastWeek) _selectedWeek = _lastWeek;
  }

  void _showWeek(int week) {
    setState(() {
      _selectedWeek = week == _calendar.weekOf(_today) ? null : week;
    });
  }

  void _finishWeekSwipe(DragEndDetails _) {
    if (_weekSwipeDistance.abs() < 48) return;
    final target = _week + (_weekSwipeDistance < 0 ? 1 : -1);
    if (target >= 1 && target <= _lastWeek) _showWeek(target);
  }

  Widget _buildTimetable({
    required int week,
    required int currentWeek,
    required List<Course> courses,
  }) {
    return GestureDetector(
      key: const ValueKey('timetable-week-swipe'),
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onHorizontalDragStart: (_) => _weekSwipeDistance = 0,
      onHorizontalDragUpdate: (details) =>
          _weekSwipeDistance += details.primaryDelta ?? 0,
      onHorizontalDragEnd: _finishWeekSwipe,
      child: Column(
        children: [
          TimetableWeekdayHeader(
            weekStart: _calendar.mondayForWeek(week),
            today: _today,
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ListView(
                  key: PageStorageKey(('timetable-scroll', week)),
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    TimetableGrid(
                      courses: courses,
                      todayWeekday: week == currentWeek ? _today.weekday : null,
                      onCourseTap: (course) =>
                          showCourseDetails(context, course),
                    ),
                  ],
                ),
                if (courses.isEmpty)
                  IgnorePointer(
                    child: Align(
                      alignment: const Alignment(0, -.30),
                      child: Chip(
                        label: Text(switch (_kind) {
                          null => '本周没有课程',
                          CourseKind.regular => '本周没有正课',
                          CourseKind.lab => '本周没有实验课',
                        }, style: const TextStyle(color: scheduleMuted)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importRegular(
    Future<void> Function(RegularScheduleImport) save,
  ) async {
    final imported = await Navigator.of(context).push<RegularScheduleImport>(
      MaterialPageRoute(
        builder: (context) => RegularScheduleImportScreen(
          readSchool: importSchoolSchedule,
          saveCourses: save,
        ),
      ),
    );
    if (!mounted || imported == null || imported.courses.isEmpty) return;
    setState(() {
      _importedRegular = imported.courses;
      _calendar = imported.calendar ?? TermCalendar.cqutFall2026;
      _selectedWeek = null;
      _kind = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入 ${imported.courses.length} 条正课安排')),
    );
  }

  Future<void> _importScreenshot(
    Future<List<Course>> Function(List<Course>) save,
  ) async {
    var updated = _importedLabs;
    final imported = await Navigator.of(context).push<List<Course>>(
      MaterialPageRoute(
        builder: (context) => LabScreenshotImportScreen(
          pickScreenshot: pickLabScreenshot,
          recognizeScreenshot: (image) async =>
              parseLabScreenshot(await recognizeLabScreenshot(image)),
          saveCourses: (courses) async {
            try {
              updated = await save(courses);
            } on Object {
              throw const FormatException('无法保存实验课，请重试。');
            }
          },
        ),
      ),
    );
    if (!mounted || imported == null || imported.isEmpty) return;
    setState(() {
      _importedLabs = updated;
      final week = imported.first.week;
      _selectedWeek = week == _calendar.weekOf(_today) ? null : week;
      _kind = CourseKind.lab;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已保存 ${imported.length} 条实验课记录')));
  }

  Future<void> _pickWeek() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: _lastWeek + 1,
          itemBuilder: (context, week) {
            if (week == 0) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '选择周次',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              );
            }
            return ListTile(
              title: Text('第 $week 周'),
              selected: week == _week,
              trailing: week == _week ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, week),
            );
          },
        ),
      ),
    );
    if (mounted && picked != null) _showWeek(picked);
  }

  @override
  Widget build(BuildContext context) {
    final routeIsCurrent = ModalRoute.isCurrentOf(context) == true;
    final update = _availableUpdate;
    if (routeIsCurrent && update != null && _offerUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_promptForUpdate(update));
      });
    }
    final week = _week;
    final currentWeek = _calendar.weekOf(_today);
    final courses = _courses
        .where((c) => c.week == week && (_kind == null || c.kind == _kind))
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScheduleHeader(
                  demoLabel: widget.isDemo && _importedRegular.isEmpty
                      ? (_importedLabs.isEmpty ? '示例课表' : '正课为示例')
                      : null,
                  onImport: widget.saveLabs == null
                      ? null
                      : () => _importScreenshot(widget.saveLabs!),
                  onImportRegular:
                      supportsSchoolScheduleImport && widget.saveRegular != null
                      ? () => _importRegular(widget.saveRegular!)
                      : null,
                  onBackup: widget.backup == null
                      ? null
                      : () => _openBackup(widget.backup!),
                  onUpdate: AppUpdate.supported ? _openUpdate : null,
                  updateAvailable: _availableUpdate != null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: week > 1 ? () => _showWeek(week - 1) : null,
                        tooltip: '上一周',
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: _pickWeek,
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 5,
                            children: [
                              Text(
                                '第 $week 周',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 19,
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: week < _lastWeek
                            ? () => _showWeek(week + 1)
                            : null,
                        tooltip: '下一周',
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 3),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final (kind, label, dot) in const [
                        (null, '全部', null),
                        (CourseKind.regular, '正课', Color(0xFF4088A0)),
                        (CourseKind.lab, '实验课', schedulePurple),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          avatar: dot == null
                              ? null
                              : Icon(Icons.circle, color: dot, size: 9),
                          showCheckmark: false,
                          selected: _kind == kind,
                          onSelected: (_) => setState(() => _kind = kind),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: scheduleLine),
                Expanded(
                  child: _buildTimetable(
                    week: week,
                    currentWeek: currentWeek,
                    courses: courses,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.demoLabel,
    required this.onImport,
    required this.onImportRegular,
    required this.onBackup,
    required this.onUpdate,
    required this.updateAvailable,
  });

  final String? demoLabel;
  final VoidCallback? onImport;
  final VoidCallback? onImportRegular;
  final VoidCallback? onBackup;
  final VoidCallback? onUpdate;
  final bool updateAvailable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '重庆理工大学',
                  style: TextStyle(color: scheduleMuted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  '周课表',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (demoLabel != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheduleLavender,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(
                  demoLabel!,
                  style: const TextStyle(color: schedulePurple, fontSize: 11),
                ),
              ),
            ),
          if (onImport != null) ...[
            const SizedBox(width: 6),
            IconButton.filledTonal(
              onPressed: onImport,
              tooltip: '导入实验课截图',
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          ],
          if (onImportRegular != null) ...[
            const SizedBox(width: 6),
            IconButton.filledTonal(
              onPressed: onImportRegular,
              tooltip: '导入正课课表',
              icon: const Icon(Icons.school_outlined),
            ),
          ],
          if (onBackup != null || onUpdate != null)
            PopupMenuButton<VoidCallback>(
              tooltip: '更多',
              icon: Badge(
                isLabelVisible: updateAvailable,
                child: const Icon(Icons.more_vert),
              ),
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                if (onBackup case final action?)
                  PopupMenuItem(value: action, child: const Text('课表备份与恢复')),
                if (onUpdate case final action?)
                  PopupMenuItem(
                    value: action,
                    child: Text(updateAvailable ? '有新版本可更新' : '检查更新'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
