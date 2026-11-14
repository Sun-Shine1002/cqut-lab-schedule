import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/course_backup_service.dart';
import '../theme/schedule_theme.dart';

class CourseBackupScreen extends StatefulWidget {
  const CourseBackupScreen({super.key, required this.backup});

  final CourseBackupService backup;

  @override
  State<CourseBackupScreen> createState() => _CourseBackupScreenState();
}

class _CourseBackupScreenState extends State<CourseBackupScreen> {
  bool _busy = false;
  String? _message;
  bool _failed = false;

  Future<void> _run(Future<void> Function() action, String fallback) async {
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = switch (error) {
          FormatException(:final message) => message,
          PlatformException(:final message) => message ?? fallback,
          _ => fallback,
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final didSave = await widget.backup.export();
    if (didSave && mounted) {
      setState(() => _message = '课表备份已保存。');
    }
  }

  Future<void> _restore() async {
    final backup = await widget.backup.chooseBackup();
    if (!mounted || backup == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复此备份？'),
        content: Text(
          '此备份有 ${backup.regularCourses.length} 条正课和 '
          '${backup.labCourses.length} 条实验课。恢复后会替换本机已导入的课表。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await widget.backup.restore(backup);
    if (mounted) Navigator.pop(context, backup);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<CourseBackupData>(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('课表备份')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '导出已导入的正课、实验课和学期日期。换手机或重新安装后，可以用备份恢复。',
                  style: TextStyle(color: scheduleMuted, height: 1.5),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(_export, '无法保存备份，请重试。'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('导出课表备份'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_restore, '无法恢复课表，请重试。'),
                  icon: const Icon(Icons.restore),
                  label: const Text('从备份恢复'),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_message case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: TextStyle(
                          color: _failed
                              ? Theme.of(context).colorScheme.error
                              : scheduleMuted,
                        ),
                      ),
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
