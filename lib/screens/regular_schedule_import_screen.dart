import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../services/regular_schedule_parser.dart';
import '../theme/schedule_theme.dart';

class RegularScheduleImportScreen extends StatefulWidget {
  const RegularScheduleImportScreen({
    super.key,
    required this.readSchool,
    required this.saveCourses,
    this.openOtherImport,
  });

  final Future<String?> Function()? readSchool;
  final Future<void> Function(RegularScheduleImport)? saveCourses;
  final Future<void> Function()? openOtherImport;

  @override
  State<RegularScheduleImportScreen> createState() =>
      _RegularScheduleImportScreenState();
}

class _RegularScheduleImportScreenState
    extends State<RegularScheduleImportScreen> {
  RegularScheduleImport? _preview;
  bool _reading = false;
  bool _saving = false;
  String? _error;

  Future<void> _readSchool() async {
    final readSchool = widget.readSchool;
    if (_reading || _saving || readSchool == null) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final source = await readSchool();
      if (!mounted || source == null) return;
      final parsed = parseRegularScheduleImport(source);
      setState(() => _preview = parsed);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error, '暂时无法读取学校课表，请稍后重试。');
      });
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save(RegularScheduleImport schedule) async {
    final saveCourses = widget.saveCourses;
    if (_reading || _saving || saveCourses == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await saveCourses(schedule);
      if (mounted) Navigator.pop(context, schedule);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error, '保存失败，请重试。'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final busy = _reading || _saving;
    final theme = Theme.of(context);
    return PopScope<Object>(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('导入正课课表')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (widget.readSchool != null) ...[
                  FilledButton.icon(
                    onPressed: busy ? null : _readSchool,
                    icon: const Icon(Icons.school_outlined),
                    label: Text(_reading ? '正在读取' : '从学校导入'),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 8, 4, 12),
                    child: Text(
                      '在学校页面登录并打开个人课表，然后点「读取课表」。',
                      style: TextStyle(color: scheduleMuted, height: 1.5),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '课程导入功能参考 GitHub 开源项目“拾光课程表”。',
                      style: TextStyle(color: scheduleMuted, height: 1.5),
                    ),
                  ),
                ],
                if (widget.openOtherImport case final openOtherImport?) ...[
                  if (widget.readSchool != null) const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: busy ? null : openOtherImport,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('其他导入'),
                  ),
                ],
                if (preview != null) ...[
                  const SizedBox(height: 16),
                  _SchedulePreview(courses: preview.courses),
                  const SizedBox(height: 12),
                  const Text(
                    '确认后将替换本机已导入的正课。',
                    style: TextStyle(color: scheduleMuted),
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
                if (preview != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : () => _save(preview),
                    child: Text(_saving ? '正在保存' : '确认导入'),
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

class _SchedulePreview extends StatelessWidget {
  const _SchedulePreview({required this.courses});

  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    final weeks = courses.map((course) => course.week).toSet().toList()..sort();
    final span = weeks.length == 1
        ? '第 ${weeks.first} 周'
        : '第 ${weeks.first}–${weeks.last} 周';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: timetableRegularFill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '读取到 ${courses.length} 个上课安排',
              style: const TextStyle(
                color: timetableRegularInk,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(span, style: const TextStyle(color: timetableRegularInk)),
          ],
        ),
      ),
    );
  }
}

String _message(Object error, String fallback) => switch (error) {
  FormatException(:final message) when message.isNotEmpty => message,
  PlatformException(:final message?) when message.isNotEmpty => message,
  _ => fallback,
};
