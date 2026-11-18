import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/course.dart';
import '../services/lab_screenshot_parser.dart';
import '../theme/schedule_theme.dart';

class LabScreenshotImportScreen extends StatefulWidget {
  const LabScreenshotImportScreen({
    super.key,
    required this.pickScreenshot,
    required this.recognizeScreenshot,
    required this.saveCourses,
  });

  final Future<Uint8List?> Function() pickScreenshot;
  final Future<List<LabCourseDraft>> Function(Uint8List screenshot)
  recognizeScreenshot;
  final Future<void> Function(List<Course> courses) saveCourses;

  @override
  State<LabScreenshotImportScreen> createState() =>
      _LabScreenshotImportScreenState();
}

class _LabScreenshotImportScreenState extends State<LabScreenshotImportScreen> {
  final _drafts = <LabCourseDraft>[];
  Uint8List? _screenshot;
  bool _picking = false;
  bool _recognizing = false;
  bool _recognized = false;
  bool _saving = false;
  String? _screenshotMessage;
  String? _saveError;

  bool get _busy => _picking || _recognizing || _saving;

  Future<void> _pickScreenshot() async {
    if (_busy) return;
    setState(() => _picking = true);
    try {
      final screenshot = await widget.pickScreenshot();
      if (!mounted || screenshot == null) return;
      setState(() {
        _screenshot = screenshot;
        _recognized = false;
        _screenshotMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _screenshotMessage = _errorMessage(error, '无法打开图片，请重试。'));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _recognizeScreenshot(Uint8List screenshot) async {
    if (_busy || _recognized) return;
    setState(() {
      _recognizing = true;
      _screenshotMessage = null;
    });
    try {
      final drafts = await widget.recognizeScreenshot(screenshot);
      if (!mounted) return;
      final count = _matchingSplitCount(drafts);
      final merge = count != null && await _confirmSplitMerge(count);
      if (!mounted) return;
      setState(() {
        if (merge) {
          final names = _drafts.first.isNameOnly ? _drafts : drafts;
          final details = _drafts.first.isDetailsOnly ? _drafts : drafts;
          final merged = [
            for (var i = 0; i < count; i++) details[i].withNameFrom(names[i]),
          ];
          _drafts
            ..clear()
            ..addAll(merged);
        } else {
          _drafts.addAll(drafts);
        }
        _recognized = drafts.isNotEmpty;
        _screenshotMessage = switch (drafts) {
          [] => '未识别到实验课程。可以换一张截图，或手动添加。',
          _ when merge => '已按顺序合并 $count 行，请核对每条课程。',
          _ when drafts.every((draft) => draft.isNameOnly) =>
            '已识别名称，请换选同一张表的周次和时间截图。',
          _ when drafts.every((draft) => draft.isDetailsOnly) =>
            '已识别时间，请换选同一张表的实验名称截图。',
          _ => null,
        };
        _saveError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _screenshotMessage = _errorMessage(error, '识别失败。可以重试或手动添加。'),
      );
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  int? _matchingSplitCount(List<LabCourseDraft> incoming) {
    if (_drafts.isEmpty || incoming.length != _drafts.length) return null;
    bool names(List<LabCourseDraft> drafts) =>
        drafts.every((draft) => draft.isNameOnly);
    bool details(List<LabCourseDraft> drafts) =>
        drafts.every((draft) => draft.isDetailsOnly);
    return (names(_drafts) && details(incoming)) ||
            (details(_drafts) && names(incoming))
        ? incoming.length
        : null;
  }

  Future<bool> _confirmSplitMerge(int count) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('按行合并两张截图？'),
          content: Text('两张截图各识别到 $count 行。确认来自同一张课表，且从上到下的行顺序一致。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('分别保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('按顺序合并'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _editDraft({int? index}) async {
    if (_busy) return;
    final edited = await showModalBottomSheet<LabCourseDraft>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _DraftEditor(
        draft: index == null ? const LabCourseDraft() : _drafts[index],
        title: index == null ? '添加实验课' : '核对实验课',
      ),
    );
    if (!mounted || edited == null) return;
    setState(() {
      if (index == null) {
        _drafts.add(edited);
      } else {
        _drafts[index] = edited;
      }
      _saveError = null;
    });
  }

  Future<void> _save() async {
    if (_busy || _drafts.isEmpty) return;
    final courses = _drafts.map((draft) => draft.toCourse()).toList();
    if (courses.contains(null)) {
      setState(() => _saveError = '请补齐标有「待补全」的课程，或移除不需要的课程。');
      return;
    }
    final verified = List<Course>.unmodifiable(courses.whereType<Course>());
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.saveCourses(verified);
      if (mounted) Navigator.pop(context, verified);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = _errorMessage(error, '保存失败，请重试。'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPreview(Uint8List screenshot) => showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('截图预览'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭预览',
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: _ScreenshotImage(bytes: screenshot),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final screenshot = _screenshot;
    return PopScope<List<Course>>(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('截图导入实验课')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _ImportPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (screenshot == null)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            '选择实验课表截图。如果名称和时间分在两张图，可以依次识别后按行合并。',
                            style: TextStyle(color: scheduleMuted),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: scheduleBackground,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _openPreview(screenshot),
                              child: SizedBox(
                                height: 176,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final ratio = MediaQuery.devicePixelRatioOf(
                                      context,
                                    );
                                    return _ScreenshotImage(
                                      bytes: screenshot,
                                      cacheWidth: (constraints.maxWidth * ratio)
                                          .ceil(),
                                      cacheHeight:
                                          (constraints.maxHeight * ratio)
                                              .ceil(),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _pickScreenshot,
                            icon: const Icon(Icons.image_outlined),
                            label: Text(screenshot == null ? '选择截图' : '更换截图'),
                          ),
                          if (screenshot != null)
                            FilledButton.icon(
                              onPressed: _busy || _recognized
                                  ? null
                                  : () => _recognizeScreenshot(screenshot),
                              icon: _recognizing
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.document_scanner_outlined),
                              label: Text(
                                _recognizing
                                    ? '正在识别'
                                    : (_recognized ? '已识别' : '识别截图'),
                              ),
                            ),
                        ],
                      ),
                      if (_screenshotMessage case final message?)
                        _InlineMessage(message),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '待核对课程（${_drafts.length}）',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _editDraft(),
                      icon: const Icon(Icons.add),
                      label: const Text('手动添加'),
                    ),
                  ],
                ),
                if (_drafts.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '点开课程核对周次和时间，再确认导入。',
                      style: TextStyle(color: scheduleMuted),
                    ),
                  ),
                for (final (index, draft) in _drafts.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DraftTile(
                      draft: draft,
                      onEdit: _busy ? null : () => _editDraft(index: index),
                      onRemove: _busy
                          ? null
                          : () => setState(() {
                              _drafts.removeAt(index);
                              _saveError = null;
                            }),
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_saveError case final message?) _InlineMessage(message),
                    FilledButton(
                      onPressed: _busy || _drafts.isEmpty ? null : _save,
                      child: Text(_saving ? '正在保存' : '确认导入'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _errorMessage(Object error, String fallback) => switch (error) {
  FormatException(:final message) when message.isNotEmpty => message,
  PlatformException(:final message?) when message.isNotEmpty => message,
  _ => fallback,
};

class _ImportPanel extends StatelessWidget {
  const _ImportPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheduleLine),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _ScreenshotImage extends StatefulWidget {
  const _ScreenshotImage({
    required this.bytes,
    this.cacheWidth,
    this.cacheHeight,
  });

  final Uint8List bytes;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  State<_ScreenshotImage> createState() => _ScreenshotImageState();
}

class _ScreenshotImageState extends State<_ScreenshotImage> {
  late ImageProvider _image = _imageProvider();

  ImageProvider _imageProvider() {
    final original = MemoryImage(widget.bytes);
    final width = widget.cacheWidth;
    final height = widget.cacheHeight;
    if (width == null || height == null) return original;
    return ResizeImage(
      original,
      width: width,
      height: height,
      policy: ResizeImagePolicy.fit,
    );
  }

  @override
  void didUpdateWidget(_ScreenshotImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bytes == oldWidget.bytes &&
        widget.cacheWidth == oldWidget.cacheWidth &&
        widget.cacheHeight == oldWidget.cacheHeight) {
      return;
    }
    unawaited(_image.evict());
    _image = _imageProvider();
  }

  @override
  void dispose() {
    unawaited(_image.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
    image: _image,
    fit: BoxFit.contain,
    semanticLabel: '实验课表截图',
    errorBuilder: (context, error, stackTrace) =>
        const Center(child: Text('无法显示该图片')),
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    required this.onEdit,
    required this.onRemove,
  });

  final LabCourseDraft draft;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final course = draft.toCourse();
    final summary = course == null
        ? '待补全'
        : '第 ${course.week} 周 · ${weekdays[course.weekday - 1]} · ${course.startTime}–${course.endTime}';
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: scheduleLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.science_outlined, color: schedulePurple),
        title: Text(draft.name.isEmpty ? '未填写实验名称' : draft.name),
        subtitle: Text(summary),
        onTap: onEdit,
        trailing: IconButton(
          onPressed: onRemove,
          tooltip: '移除这门实验课',
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _DraftEditor extends StatefulWidget {
  const _DraftEditor({required this.draft, required this.title});

  final LabCourseDraft draft;
  final String title;

  @override
  State<_DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends State<_DraftEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.draft.name);
  late final _week = TextEditingController(text: widget.draft.week?.toString());
  late final _start = TextEditingController(text: widget.draft.startTime);
  late final _end = TextEditingController(text: widget.draft.endTime);
  late final _location = TextEditingController(text: widget.draft.location);
  late final _teacher = TextEditingController(text: widget.draft.teacher);
  late final _grade = TextEditingController(text: widget.draft.grade);
  late final _evaluation = TextEditingController(text: widget.draft.evaluation);
  late int? _weekday = switch (widget.draft.weekday) {
    final int day when day >= 1 && day <= weekdays.length => day,
    _ => null,
  };

  static final _clock = RegExp(r'^([0-9]{1,2})\s*:\s*([0-9]{2})$');

  @override
  void dispose() {
    for (final controller in [
      _name,
      _week,
      _start,
      _end,
      _location,
      _teacher,
      _grade,
      _evaluation,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _normalizeNumbers(String input) {
    return String.fromCharCodes(
      input.trim().codeUnits.map((unit) {
        return switch (unit) {
          >= 0xFF10 && <= 0xFF19 => unit - 0xFEE0,
          0xFF1A => 0x3A,
          _ => unit,
        };
      }),
    );
  }

  static int? _minutes(String input) {
    final time = _clock.firstMatch(_normalizeNumbers(input));
    if (time == null) return null;
    final hours = int.parse(time[1]!);
    final minutes = int.parse(time[2]!);
    return hours < 24 && minutes < 60 ? hours * 60 + minutes : null;
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      LabCourseDraft(
        name: _name.text.trim(),
        week: int.parse(_normalizeNumbers(_week.text)),
        weekday: _weekday,
        startTime: _normalizeNumbers(_start.text),
        endTime: _normalizeNumbers(_end.text),
        location: _location.text.trim(),
        teacher: _teacher.text.trim(),
        grade: _grade.text.trim(),
        evaluation: _evaluation.text.trim(),
        sourceText: widget.draft.sourceText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + keyboard),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              if (widget.draft.sourceText.isNotEmpty)
                _ImportPanel(
                  child: Text(
                    widget.draft.sourceText,
                    style: const TextStyle(color: scheduleMuted),
                  ),
                ),
              _field(
                _name,
                '实验名称',
                validator: (value) => value!.trim().isEmpty ? '请输入实验名称' : null,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Expanded(
                    child: _field(
                      _week,
                      '周次',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final week = int.tryParse(
                          _normalizeNumbers(value ?? ''),
                        );
                        return week == null || week < 1 || week > 53
                            ? '请输入 1–53'
                            : null;
                      },
                    ),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _weekday,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '星期',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final (index, label) in weekdays.indexed)
                          DropdownMenuItem(
                            value: index + 1,
                            child: Text(label),
                          ),
                      ],
                      onChanged: (value) => _weekday = value,
                      validator: (value) => value == null ? '请选择星期' : null,
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Expanded(
                    child: _field(
                      _start,
                      '开始时间',
                      hint: '13:50',
                      keyboardType: TextInputType.datetime,
                      validator: (value) =>
                          _minutes(value ?? '') == null ? '请输入有效时间' : null,
                    ),
                  ),
                  Expanded(
                    child: _field(
                      _end,
                      '结束时间',
                      hint: '16:05',
                      keyboardType: TextInputType.datetime,
                      validator: (value) {
                        final end = _minutes(value ?? '');
                        if (end == null) return '请输入有效时间';
                        final start = _minutes(_start.text);
                        return start != null && end <= start ? '应晚于开始时间' : null;
                      },
                    ),
                  ),
                ],
              ),
              _field(_location, '实验地点（选填）'),
              _field(_teacher, '任课教师（选填）'),
              Row(
                spacing: 10,
                children: [
                  Expanded(child: _field(_grade, '成绩（选填）')),
                  Expanded(child: _field(_evaluation, '评教（选填）')),
                ],
              ),
              FilledButton(onPressed: _confirm, child: const Text('保存课程')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );
}
