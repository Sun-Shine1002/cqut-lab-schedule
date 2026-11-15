import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/term_calendar.dart';
import '../services/app_update.dart';
import '../services/course_backup_service.dart';
import '../services/course_document_parser.dart';
import '../services/lab_screenshot_parser.dart';
import '../services/regular_schedule_parser.dart';
import '../services/school_schedule_import.dart';
import '../services/screenshot_ocr.dart';
import '../theme/schedule_theme.dart';
import '../widgets/course_card.dart';
import '../widgets/timetable_grid.dart';
import 'app_update_screen.dart';
import 'course_backup_screen.dart';
import 'course_document_import_screen.dart';
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
    this.readSchoolLabs,
    this.saveRegular,
    this.readCourseDocument,
    this.saveDocumentCourses,
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
  final Future<List<Course>?> Function()? readSchoolLabs;
  final Future<void> Function(RegularScheduleImport)? saveRegular;
  final Future<Map<String, CourseDocumentClass>?> Function()?
  readCourseDocument;
  final Future<CourseBackupData> Function(List<Course>)? saveDocumentCourses;
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
  late final PageController _weekPages;
  late TermCalendar _calendar;
  late DateTime _today;
  late List<Course> _importedLabs;
  late List<Course> _importedRegular;
  CourseKind? _kind;
  AppRelease? _availableUpdate;
  bool _startupCheckStarted = false;
  bool _offerUpdate = false;
  bool _updateScreenOpen = false;

  bool get _canCheckForUpdate =>
      widget.checkForUpdate != null ||
      (AppUpdate.supported && AppUpdate.configured);

  bool get _canImportRegular =>
      (supportsSchoolScheduleImport && widget.saveRegular != null) ||
      (widget.readCourseDocument != null && widget.saveDocumentCourses != null);

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
    _weekPages = PageController(initialPage: _week - 1, keepPage: false);
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
    _syncWeekPage();
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
    _weekPages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final today = (widget.now ?? DateTime.now)();
    if (!DateUtils.isSameDay(_today, today)) {
      setState(() => _today = today);
      _syncWeekPage();
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
    final previousWeek = _week;
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
    if (_week != previousWeek) _syncWeekPage();
  }

  void _showWeek(int week) {
    if (week == _week || !_weekPages.hasClients) return;
    if ((week - _week).abs() == 1) {
      unawaited(
        _weekPages.animateToPage(
          week - 1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _weekPages.jumpToPage(week - 1);
    }
  }

  void _syncWeekPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _weekPages.hasClients) {
        _weekPages.jumpToPage(_week - 1);
      }
    });
  }

  void _onWeekPageChanged(int page) {
    final week = page + 1;
    if (week == _week) return;
    setState(() {
      _selectedWeek = week == _calendar.weekOf(_today) ? null : week;
    });
  }

  Widget _buildTimetable({
    required int week,
    required int currentWeek,
    required List<Course> courses,
  }) {
    return ColoredBox(
      color: scheduleBackground,
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
                  primary: false,
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
                if (courses.isEmpty && _kind != null)
                  IgnorePointer(
                    child: Align(
                      alignment: const Alignment(0, -.30),
                      child: Chip(
                        label: Text(
                          _kind == CourseKind.regular ? '本周没有正课' : '本周没有实验课',
                          style: const TextStyle(color: scheduleMuted),
                        ),
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

  Future<void> _importRegular() async {
    final readFile = widget.readCourseDocument;
    final saveFromFile = widget.saveDocumentCourses;
    final saveSchool = widget.saveRegular;
    CourseBackupData? savedDocument;
    final imported = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (importContext) => RegularScheduleImportScreen(
          readSchool: supportsSchoolScheduleImport && saveSchool != null
              ? importSchoolSchedule
              : null,
          saveCourses: saveSchool,
          openOtherImport: readFile != null && saveFromFile != null
              ? () async {
                  final selected = await Navigator.of(importContext)
                      .push<List<Course>>(
                        MaterialPageRoute(
                          builder: (context) => CourseDocumentImportScreen(
                            readFile: readFile,
                            termCalendar: _calendar,
                            saveCourses: (courses) async {
                              savedDocument = await saveFromFile(courses);
                            },
                          ),
                        ),
                      );
                  if (importContext.mounted && selected != null) {
                    Navigator.pop<Object>(importContext, selected);
                  }
                }
              : null,
        ),
      ),
    );
    if (!mounted) return;
    final saved = savedDocument;
    if (imported is List<Course> && imported.isNotEmpty && saved != null) {
      setState(() {
        _importedRegular = saved.regularCourses;
        _importedLabs = saved.labCourses;
        final week = imported.first.week;
        _selectedWeek = week == _calendar.weekOf(_today) ? null : week;
        _kind = null;
      });
      _syncWeekPage();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 ${imported.length} 条文件课程')));
      return;
    }
    if (imported is! RegularScheduleImport || imported.courses.isEmpty) return;
    setState(() {
      _importedRegular = imported.courses;
      _calendar = imported.calendar ?? TermCalendar.cqutFall2026;
      _selectedWeek = null;
      _kind = null;
    });
    _syncWeekPage();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入 ${imported.courses.length} 条正课安排')),
    );
  }

  Future<void> _importLabs(
    Future<List<Course>> Function(List<Course>) save,
  ) async {
    final readSchool = widget.readSchoolLabs;
    final method = await showModalBottomSheet<_LabImportMethod>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '导入实验课',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (readSchool != null)
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('直接导入'),
                subtitle: const Text('请先连接校园网，点击跳转登录实验选课系统。'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, _LabImportMethod.direct),
              ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('截图导入'),
              subtitle: const Text('识别实验课表截图，核对后保存。'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, _LabImportMethod.screenshot),
            ),
          ],
        ),
      ),
    );
    if (!mounted || method == null) return;

    var updated = _importedLabs;
    Future<void> saveCourses(List<Course> courses) async {
      try {
        updated = await save(courses);
      } on Object {
        throw const FormatException('无法保存实验课，请重试。');
      }
    }

    final imported = await Navigator.of(context).push<List<Course>>(
      MaterialPageRoute(
        builder: (context) =>
            method == _LabImportMethod.direct && readSchool != null
            ? _LabDirectImportScreen(
                readSchool: readSchool,
                saveCourses: saveCourses,
              )
            : LabScreenshotImportScreen(
                pickScreenshot: pickLabScreenshot,
                recognizeScreenshot: (image) async =>
                    parseLabScreenshot(await recognizeLabScreenshot(image)),
                saveCourses: saveCourses,
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
    _syncWeekPage();
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
    final coursesByWeek = <int, List<Course>>{};
    for (final course in _courses) {
      if (_kind == null || course.kind == _kind) {
        (coursesByWeek[course.week] ??= []).add(course);
      }
    }

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
                      : () => _importLabs(widget.saveLabs!),
                  onImportRegular: _canImportRegular ? _importRegular : null,
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
                  child: PageView.builder(
                    key: const ValueKey('timetable-week-swipe'),
                    controller: _weekPages,
                    physics: const ClampingScrollPhysics(),
                    itemCount: _lastWeek,
                    onPageChanged: _onWeekPageChanged,
                    itemBuilder: (context, index) {
                      final pageWeek = index + 1;
                      return _buildTimetable(
                        week: pageWeek,
                        currentWeek: currentWeek,
                        courses: coursesByWeek[pageWeek] ?? const [],
                      );
                    },
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

enum _LabImportMethod { direct, screenshot }

class _LabDirectImportScreen extends StatefulWidget {
  const _LabDirectImportScreen({
    required this.readSchool,
    required this.saveCourses,
  });

  final Future<List<Course>?> Function() readSchool;
  final Future<void> Function(List<Course>) saveCourses;

  @override
  State<_LabDirectImportScreen> createState() => _LabDirectImportScreenState();
}

class _LabDirectImportScreenState extends State<_LabDirectImportScreen> {
  List<Course> _courses = const [];
  bool _reading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_readSchool());
    });
  }

  Future<void> _readSchool() async {
    if (_reading || _saving) return;
    setState(() {
      _reading = true;
      _error = null;
      _courses = const [];
    });
    try {
      final result = await widget.readSchool();
      if (!mounted || result == null) return;
      setState(() {
        _courses = result;
        if (result.isEmpty) _error = '没有读到实验课，请在学校页面打开实验课表。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error) {
          FormatException(:final message) when message.isNotEmpty => message,
          PlatformException(:final message?) when message.isNotEmpty => message,
          _ => '暂时无法读取实验课表，请检查校园网连接后重试。',
        };
      });
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save() async {
    if (_reading || _saving || _courses.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.saveCourses(_courses);
      if (mounted) Navigator.pop(context, _courses);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '无法保存实验课，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _reading || _saving;
    return PopScope<List<Course>>(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('直接导入实验课')),
        bottomNavigationBar: _courses.isEmpty
            ? null
            : SafeArea(
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: busy ? null : _save,
                          child: Text(_saving ? '正在保存' : '确认导入'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                if (_courses.isEmpty) ...[
                  const Text(
                    '请先连接校园网，再登录实验选课系统。如未显示课表，请打开「课程管理 → 课表及成绩查询」。',
                    style: TextStyle(color: scheduleMuted, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : _readSchool,
                    icon: const Icon(Icons.school_outlined),
                    label: Text(_reading ? '正在打开…' : '打开实验选课系统'),
                  ),
                ],
                if (_error case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                if (_courses.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    '读取到 ${_courses.length} 条实验课，请核对后导入。',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  for (final course in _courses)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.science_outlined,
                        color: schedulePurple,
                      ),
                      title: Text(course.name),
                      subtitle: Text(
                        '第 ${course.week} 周 · ${weekdays[course.weekday - 1]}\n'
                        '${course.startTime}–${course.endTime}'
                        '${course.location.isEmpty ? '' : ' · ${course.location}'}',
                      ),
                      isThreeLine: true,
                    ),
                ],
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
              tooltip: '导入实验课',
              icon: const Icon(Icons.science_outlined),
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
