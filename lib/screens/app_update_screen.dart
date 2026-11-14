import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/app_update.dart';

const _scanInstructions = '如果系统弹出 Google Play 保护机制提示，请点「扫描应用」，等扫描完成后按系统提示继续安装。';

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key, this.available});

  final AppRelease? available;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  AppUpdateInfo? _installed;
  AppRelease? _release;
  String? _readyPath;
  String? _message;
  double? _progress;
  var _checking = false;
  var _downloading = false;
  var _installing = false;
  var _needsPermission = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check(useAvailable: true));
  }

  Future<void> _check({bool useAvailable = false}) async {
    setState(() {
      _checking = true;
      _release = null;
      _readyPath = null;
      _needsPermission = false;
      _message = null;
    });
    try {
      final installed = await AppUpdate.info();
      if (!mounted) return;
      setState(() => _installed = installed);
      if (!AppUpdate.configured) {
        setState(() => _message = '此版本尚未配置更新地址。');
        return;
      }
      final release = useAvailable && widget.available != null
          ? widget.available
          : await AppUpdate.check(installed);
      if (!mounted) return;
      setState(() {
        _release = release;
        if (release == null) _message = '已是最新版本。';
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on Exception {
      if (mounted) setState(() => _message = '暂时无法检查更新，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _update() async {
    final installed = _installed!;
    final release = _release!;
    var path = _readyPath;
    setState(() {
      _message = null;
      _needsPermission = false;
      _progress = null;
      _downloading = path == null;
      _installing = path != null;
    });
    try {
      path ??= await AppUpdate.download(installed, release, (received, total) {
        if (!mounted || total == null) return;
        final progress = (received / total).clamp(0.0, 1.0);
        if (_progress == null || progress - _progress! >= .01) {
          setState(() => _progress = progress);
        }
      });
      if (!mounted) return;
      setState(() {
        _readyPath = path;
        _downloading = false;
        _installing = true;
      });
      await AppUpdate.install(path, release);
      if (mounted) setState(() => _message = '请在 Android 安装界面确认。');
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _needsPermission = error.code == 'INSTALL_PERMISSION_REQUIRED';
        if (!_needsPermission) _readyPath = null;
        _message = _needsPermission
            ? '请在系统设置中允许课表 App 安装应用，返回后再点「安装更新」。'
            : error.message ?? '无法安装更新，请重试。';
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on TimeoutException {
      if (mounted) setState(() => _message = '下载超时，请切换网络后重试。');
    } on Exception {
      if (mounted) setState(() => _message = '下载中断，请检查网络后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _installing = false;
        });
      }
    }
  }

  Future<void> _openSettings() async {
    try {
      await AppUpdate.openInstallSettings();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _message = error.message ?? '无法打开系统设置。');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    final busy = _checking || _downloading || _installing;
    return PopScope(
      canPop: !_downloading,
      child: Scaffold(
        appBar: AppBar(title: const Text('应用更新')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_installed case final installed?)
                  Text('当前版本 ${installed.versionName}'),
                if (release != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '可更新至 ${release.versionName}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (release.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(release.notes),
                    ),
                ],
                if (_checking || _downloading) ...[
                  const SizedBox(height: 16),
                  Text(_checking ? '正在检查更新…' : '正在下载安装包…'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _progress),
                ],
                if (_message case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(message),
                  ),
                const SizedBox(height: 16),
                if (release != null) ...[
                  FilledButton(
                    onPressed: busy ? null : _update,
                    child: Text(_readyPath == null ? '下载并安装' : '安装更新'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scanInstructions,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_needsPermission)
                  OutlinedButton(
                    onPressed: _openSettings,
                    child: const Text('打开系统设置'),
                  ),
                if (AppUpdate.configured)
                  TextButton(
                    onPressed: busy ? null : _check,
                    child: const Text('检查更新'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
