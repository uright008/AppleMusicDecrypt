import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

const _defaultApiUrl = 'http://127.0.0.1:10020';
const _codecs = <String>[
  'alac',
  'ec3',
  'ac3',
  'aac',
  'aac-binaural',
  'aac-downmix',
  'aac-legacy',
];
const _languages = <String>[
  'zh-Hans-CN',
  'zh-Hant-HK',
  'zh-Hant-TW',
  'en-US',
  'en-GB',
  'ja',
  'ko',
];

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.initialApiUrl,
    this.onApiUrlChanged,
  });

  final String? initialApiUrl;
  final Future<void> Function(String value)? onApiUrlChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlController = TextEditingController();
  ApiClient? _api;
  Timer? _timer;
  String _apiUrl = _defaultApiUrl;
  String _codec = 'alac';
  String _language = 'zh-Hant-HK';
  bool _force = false;
  bool _includeParticipateSongs = false;
  bool _submitting = false;
  ServerStatus? _serverStatus;
  TaskSnapshot _snapshot = const TaskSnapshot(
    tasks: [],
    downloadSpeed: '0.00 kB/s',
    decryptSpeed: '0.00 kB/s',
    running: 0,
  );
  String? _connectionError;
  int _apiGeneration = 0;
  int _refreshRequestId = 0;
  int _lastAppliedRefreshRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final savedApiUrl = widget.initialApiUrl ??
        await SharedPreferencesAsync().getString('apiUrl') ??
        _defaultApiUrl;
    if (!mounted) return;
    try {
      _replaceApi(savedApiUrl);
    } on FormatException {
      _replaceApi(_defaultApiUrl);
      await _persistApiUrl(_defaultApiUrl);
    }
    await _refresh();
    if (!mounted) return;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _persistApiUrl(String value) async {
    final onApiUrlChanged = widget.onApiUrlChanged;
    if (onApiUrlChanged != null) {
      await onApiUrlChanged(value);
      return;
    }
    await SharedPreferencesAsync().setString('apiUrl', value);
  }

  void _replaceApi(String value) {
    final nextApi = ApiClient(baseUrl: value);
    final previousApi = _api;
    _api = nextApi;
    _apiUrl = nextApi.baseUrl;
    _apiGeneration++;
    previousApi?.close();
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null) return;
    final generation = _apiGeneration;
    final requestId = ++_refreshRequestId;
    try {
      final results = await Future.wait<dynamic>([api.health(), api.tasks()]);
      if (!mounted ||
          generation != _apiGeneration ||
          requestId < _lastAppliedRefreshRequestId) {
        return;
      }
      _lastAppliedRefreshRequestId = requestId;
      setState(() {
        _serverStatus = results[0] as ServerStatus;
        _snapshot = results[1] as TaskSnapshot;
        _connectionError = null;
      });
    } catch (error) {
      if (!mounted ||
          generation != _apiGeneration ||
          requestId < _lastAppliedRefreshRequestId) {
        return;
      }
      _lastAppliedRefreshRequestId = requestId;
      setState(() {
        _serverStatus = null;
        _connectionError = error.toString();
      });
    }
  }

  Future<void> _enqueue() async {
    final urls = _urlController.text
        .split(RegExp(r'[\s,]+'))
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty) {
      _showMessage('请粘贴 Apple Music 链接');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _api!.enqueue(
        urls: urls,
        codec: _codec,
        language: _language,
        force: _force,
        includeParticipateSongs: _includeParticipateSongs,
      );
      _urlController.clear();
      _showMessage('已加入下载队列');
      await _refresh();
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancel(DownloadTask task) async {
    try {
      await _api!.cancel(task.adamId);
      await _refresh();
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _editSettings() async {
    final next = await showDialog<String>(
      context: context,
      builder: (context) => _BackendSettingsDialog(initialUrl: _apiUrl),
    );
    if (!mounted || next == null) return;
    try {
      _replaceApi(next);
      setState(() {
        _serverStatus = null;
        _connectionError = null;
      });
      await _persistApiUrl(_apiUrl);
      await _refresh();
    } on FormatException catch (error) {
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api?.close();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AppleMusicDecrypt'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: _editSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ConnectionCard(status: _serverStatus, error: _connectionError),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('新建下载', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Apple Music 链接',
                        hintText: '可粘贴多个链接，以空格或换行分隔',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final codecDropdown = DropdownButtonFormField<String>(
                          initialValue: _codec,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '编码'),
                          items: _codecs
                              .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(growable: false),
                          onChanged: (value) =>
                              setState(() => _codec = value!),
                        );
                        final languageDropdown =
                            DropdownButtonFormField<String>(
                          initialValue: _language,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: '元数据语言'),
                          items: _languages
                              .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(growable: false),
                          onChanged: (value) =>
                              setState(() => _language = value!),
                        );
                        if (constraints.maxWidth < 420) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              codecDropdown,
                              const SizedBox(height: 12),
                              languageDropdown,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: codecDropdown),
                            const SizedBox(width: 12),
                            Expanded(child: languageDropdown),
                          ],
                        );
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('覆盖已有文件'),
                      value: _force,
                      onChanged: (value) => setState(() => _force = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('艺人链接包含参与作品'),
                      value: _includeParticipateSongs,
                      onChanged: (value) =>
                          setState(() => _includeParticipateSongs = value),
                    ),
                    FilledButton.icon(
                      onPressed: _submitting || _serverStatus?.ready != true
                          ? null
                          : _enqueue,
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: const Text('加入队列'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SpeedRow(snapshot: _snapshot),
            const SizedBox(height: 12),
            Text('任务', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_snapshot.tasks.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('暂无任务')),
                ),
              )
            else
              ..._snapshot.tasks.map(
                (task) => _TaskCard(task: task, onCancel: () => _cancel(task)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackendSettingsDialog extends StatefulWidget {
  const _BackendSettingsDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_BackendSettingsDialog> createState() =>
      _BackendSettingsDialogState();
}

class _BackendSettingsDialogState extends State<_BackendSettingsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('后端设置'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: const InputDecoration(
          labelText: 'API 地址',
          helperText: '默认使用本机 Termux 服务',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.status, required this.error});

  final ServerStatus? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final connected = status?.ready == true;
    final color = connected ? Colors.green : Theme.of(context).colorScheme.error;
    return Card(
      child: ListTile(
        leading: Icon(connected ? Icons.cloud_done : Icons.cloud_off, color: color),
        title: Text(connected ? '后端已连接' : '后端未连接'),
        subtitle: Text(
          connected
              ? '${status!.manager} · ${status!.regions.join(', ')}'
              : (error ?? '正在连接本机 API…'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _SpeedRow extends StatelessWidget {
  const _SpeedRow({required this.snapshot});

  final TaskSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Metric(label: '下载', value: snapshot.downloadSpeed)),
        const SizedBox(width: 8),
        Expanded(child: _Metric(label: '解密', value: snapshot.decryptSpeed)),
        const SizedBox(width: 8),
        Expanded(child: _Metric(label: '运行中', value: '${snapshot.running}')),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onCancel});

  final DownloadTask task;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final title = task.title?.isNotEmpty == true ? task.title! : task.adamId;
    final subtitle = [task.artist, task.album, task.error]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' · ');
    return Card(
      child: ListTile(
        leading: _StatusIcon(status: task.status),
        title: Text(title),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: task.canCancel
            ? IconButton(
                tooltip: '取消',
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined),
              )
            : Text(task.status),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      'DONE' => const Icon(Icons.check_circle, color: Colors.green),
      'FAILED' || 'KILLED' =>
        Icon(Icons.error, color: Theme.of(context).colorScheme.error),
      'DOWNLOADING' => const Icon(Icons.downloading),
      'DECRYPTING' => const Icon(Icons.lock_open),
      _ => const Icon(Icons.schedule),
    };
  }
}
