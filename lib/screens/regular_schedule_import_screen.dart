import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../services/regular_schedule_parser.dart';
import '../theme/schedule_theme.dart';

class RegularScheduleImportScreen extends StatefulWidget {
  const RegularScheduleImportScreen({
    super.key,
    required this.pickFile,
    this.readSchool,
    required this.saveCourses,
  });

  final Future<String?> Function() pickFile;
  final Future<String?> Function()? readSchool;
  final Future<void> Function(RegularScheduleImport) saveCourses;

  @override
  State<RegularScheduleImportScreen> createState() =>
      _RegularScheduleImportScreenState();
}

class _RegularScheduleImportScreenState
    extends State<RegularScheduleImportScreen> {
  RegularScheduleImport? _preview;
  bool _picking = false;
  bool _saving = false;
  String? _error;

  Future<void> _pick(
    Future<String?> Function() read,
    String failureMessage,
  ) async {
    if (_picking || _saving) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final source = await read();
      if (!mounted || source == null) return;
      final parsed = parseRegularScheduleImport(source);
      setState(() => _preview = parsed);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error, failureMessage);
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save(RegularScheduleImport schedule) async {
    if (_picking || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.saveCourses(schedule);
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
    final busy = _picking || _saving;
    final theme = Theme.of(context);
    return PopScope<RegularScheduleImport>(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('导入正课课表')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (widget.readSchool case final read?) ...[
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => _pick(read, '暂时无法读取学校课表，请稍后重试。'),
                    icon: const Icon(Icons.school_outlined),
                    label: const Text('从学校导入'),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 8, 4, 20),
                    child: Text(
                      '在学校页面登录并打开个人课表，然后点「读取课表」。',
                      style: TextStyle(color: scheduleMuted, height: 1.5),
                    ),
                  ),
                ],
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(color: scheduleLine),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('拾光课程表文件', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text(
                          '在拾光课程表的「我的 → 高级功能 → 课表导入/导出」导出 JSON，然后选择该文件。',
                          style: TextStyle(color: scheduleMuted, height: 1.5),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => _pick(widget.pickFile, '无法打开课表文件，请重新选择。'),
                          icon: const Icon(Icons.file_open_outlined),
                          label: Text(_picking ? '正在读取' : '选择 JSON 文件'),
                        ),
                      ],
                    ),
                  ),
                ),
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
