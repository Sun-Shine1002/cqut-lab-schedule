import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../models/term_calendar.dart';
import '../services/course_document_parser.dart';
import '../theme/schedule_theme.dart';

class CourseDocumentImportScreen extends StatefulWidget {
  const CourseDocumentImportScreen({
    super.key,
    required this.readFile,
    required this.saveCourses,
    this.termCalendar,
  });

  final Future<Map<String, CourseDocumentClass>?> Function() readFile;
  final Future<void> Function(List<Course>) saveCourses;
  final TermCalendar? termCalendar;

  @override
  State<CourseDocumentImportScreen> createState() =>
      _CourseDocumentImportScreenState();
}

class _CourseDocumentImportScreenState
    extends State<CourseDocumentImportScreen> {
  Map<String, CourseDocumentClass> _classes = const {};
  String? _selectedClass;
  final _selectedOptions = <(int, int)>{};
  bool _reading = false;
  bool _saving = false;
  String? _error;

  bool get _busy => _reading || _saving;
  TermCalendar get _calendar =>
      widget.termCalendar ?? TermCalendar.cqutFall2026;

  List<Course> get _otherCourses =>
      _classes[_selectedClass]?.courses ?? const [];
  List<List<List<Course>>> get _sessionChoices =>
      _classes[_selectedClass]?.alternatives ?? const [];

  int get _pendingChoices =>
      _sessionChoices.length -
      _selectedOptions.map((selection) => selection.$1).toSet().length;

  Iterable<Course> get _selectedCourses sync* {
    yield* _otherCourses;
    for (final (group, option) in _selectedOptions) {
      yield* _sessionChoices[group][option];
    }
  }

  Future<void> _readFile() async {
    if (_busy) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final source = await widget.readFile();
      if (!mounted || source == null) return;
      final classes = {
        for (final entry in source.entries)
          if (entry.value.courses.isNotEmpty ||
              entry.value.alternatives.isNotEmpty)
            entry.key: entry.value,
      };
      if (classes.isEmpty) {
        throw const FormatException('文件中没有读到课程，请检查课表内容。');
      }
      setState(() {
        _classes = classes;
        _selectClass(classes.length == 1 ? classes.keys.single : null);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error) {
          FormatException(:final message) when message.isNotEmpty => message,
          PlatformException(:final message?) when message.isNotEmpty => message,
          _ => '无法读取这个课表文件，请检查格式后重试。',
        };
      });
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _selectClass(String? name) {
    _selectedClass = name;
    _selectedOptions.clear();
  }

  static int _chronological(Course a, Course b) {
    final week = a.week.compareTo(b.week);
    if (week != 0) return week;
    final day = a.weekday.compareTo(b.weekday);
    return day == 0 ? a.startTime.compareTo(b.startTime) : day;
  }

  Future<void> _save() async {
    if (_busy || _pendingChoices > 0) return;
    final selected = _selectedCourses.toList()..sort(_chronological);
    if (selected.isEmpty) return;
    final courses = List<Course>.unmodifiable(selected);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.saveCourses(courses);
      if (mounted) Navigator.pop(context, courses);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('课表保存失败，请重试。')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _when(Course course) {
    final date = _calendar
        .mondayForWeek(course.week)
        .add(Duration(days: course.weekday - DateTime.monday));
    return '${date.month} 月 ${date.day} 日 · ${weekdays[course.weekday - 1]}'
        ' · ${course.startTime}–${course.endTime}';
  }

  String _courseSlot(Course course) =>
      '${_when(course)}${course.location.isEmpty ? '' : '\n${course.location}'}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _selectedCourses.length;
    final pending = _pendingChoices;
    final otherCourses = _otherCourses.toList()..sort(_chronological);
    return PopScope<List<Course>>(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('文件导入课表')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _readFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(_reading ? '正在读取' : '选择 Excel 或 Word 文件'),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Text(
                    '支持 .xlsx 工作表和 .docx 文档中的课表表格。',
                    style: TextStyle(color: scheduleMuted),
                  ),
                ),
                if (_classes.length > 1) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ObjectKey(_classes),
                    initialValue: _selectedClass,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '选择班级',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final name in _classes.keys)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: _busy
                        ? null
                        : (name) {
                            if (name != _selectedClass) {
                              setState(() => _selectClass(name));
                            }
                          },
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
                if (_selectedClass != null) ...[
                  const SizedBox(height: 18),
                  Text('课程预览', style: theme.textTheme.titleLarge),
                  if (_classes.length == 1) Text(_selectedClass!),
                ],
                if (_sessionChoices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '有些实验安排了多个批次，请勾选你实际要上的安排。每组选一项或多项。',
                    style: TextStyle(color: scheduleMuted, height: 1.5),
                  ),
                  for (final (groupIndex, group) in _sessionChoices.indexed)
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Text(
                              group.first.first.name,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          for (final (optionIndex, courses) in group.indexed)
                            CheckboxListTile(
                              title: Text(
                                '第 ${(courses.map((course) => course.week).toSet().toList()..sort()).join('、')} 周',
                              ),
                              subtitle: Text(
                                courses.map(_courseSlot).join('\n'),
                              ),
                              value: _selectedOptions.contains((
                                groupIndex,
                                optionIndex,
                              )),
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                      final option = (groupIndex, optionIndex);
                                      if (value == true) {
                                        _selectedOptions.add(option);
                                      } else {
                                        _selectedOptions.remove(option);
                                      }
                                    }),
                            ),
                        ],
                      ),
                    ),
                ],
                for (final course in otherCourses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      course.kind == CourseKind.lab
                          ? Icons.science_outlined
                          : Icons.school_outlined,
                      color: schedulePurple,
                    ),
                    title: Text(course.name),
                    subtitle: Text(
                      '第 ${course.week} 周 · ${_courseSlot(course)}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _selectedClass == null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 608),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (pending > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              '还有 $pending 组实验待选择时段',
                              style: const TextStyle(color: scheduleMuted),
                            ),
                          ),
                        FilledButton(
                          onPressed: _busy || pending > 0 || selectedCount == 0
                              ? null
                              : _save,
                          child: Text(
                            _saving ? '正在保存' : '确认导入 $selectedCount 条课程',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
