import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_layout.dart';
import 'adaptive_text_field.dart';
import 'core_bridge.dart';
import 'download_collections.dart';
import 'local_store.dart';
import 'local_media_screen.dart';
import 'models.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';
import 'remote_widgets.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    required this.repository,
    required this.store,
    this.embedded = false,
    this.playerBuilder,
    this.searchFocusNode,
    this.onSearchUp,
  });
  final AppRepository repository;
  final LocalStore store;
  final bool embedded;
  final FocusNode? searchFocusNode;
  final VoidCallback? onSearchUp;
  @visibleForTesting
  final Widget Function(DramaDetail, int, double)? playerBuilder;
  @override
  State<DownloadsScreen> createState() => DownloadsScreenState();
}

class DownloadsScreenState extends State<DownloadsScreen> {
  Timer? _timer;
  final _search = TextEditingController();
  final _selected = <String>{};
  final _expanded = <String>{};
  late final DownloadCollectionUpdater _updater;
  late final int _epoch;
  List<DownloadJob> _jobs = [];
  bool _loading = true,
      _refreshing = false,
      _opening = false,
      _selecting = false,
      _busy = false,
      _stopBatch = false;
  String? _error, _retryCommand;
  String _filter = 'all', _release = '', _operation = '';
  FocusNode? _ownedTvSearchFocus,
      _ownedTvReturnFocus,
      _ownedTvStopFocus,
      _ownedTvBatchFocus;
  FocusScopeNode? _ownedTvContentFocus;
  final _tvFilterNodes = <String, FocusNode>{};
  String? _tvCollectionId;
  final _tvTitle = ValueNotifier<String>('');
  FocusNode get _tvSearchFocus =>
      widget.searchFocusNode ??
      (_ownedTvSearchFocus ??= FocusNode(debugLabel: 'tv-download-search'));
  FocusNode get _tvReturnFocus =>
      _ownedTvReturnFocus ??= FocusNode(debugLabel: 'tv-download-return');
  FocusNode get _tvStopFocus =>
      _ownedTvStopFocus ??= FocusNode(debugLabel: 'tv-download-stop');
  FocusNode get _tvBatchFocus =>
      _ownedTvBatchFocus ??= FocusNode(debugLabel: 'tv-download-batch');
  FocusScopeNode get _tvContentFocus => _ownedTvContentFocus ??= FocusScopeNode(
    debugLabel: 'tv-download-content',
  );
  FocusNode _tvFilterFocus(String id) => _tvFilterNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'tv-download-filter-$id'),
  );

  void _exitSelection() => setState(() {
    _selecting = false;
    _selected.clear();
    _retryCommand = null;
  });

  void _focusTvContent() {
    if (_ownedTvContentFocus?.context == null ||
        !_tvContentFocus.traversalDescendants.any(
          (node) => node.canRequestFocus && !node.skipTraversal,
        )) {
      _tvFilterFocus(_filter).requestFocus();
      return;
    }
    final previous = _tvContentFocus.focusedChild;
    _tvContentFocus.requestFocus();
    if (previous == null) _tvContentFocus.nextFocus();
  }

  void _closeTvCollection() {
    setState(() => _tvCollectionId = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusTvContent();
    });
  }

  bool handleTelevisionBack() {
    if (!mounted || !AppLayout.isTelevision(context)) return false;
    if (_selecting) {
      if (_busy) {
        setState(() => _stopBatch = true);
      } else {
        _exitSelection();
      }
      return true;
    }
    if (_tvCollectionId != null) {
      _closeTvCollection();
      return true;
    }
    return false;
  }

  bool get _allowed =>
      widget.store.profileEpoch == _epoch && widget.store.canDownload;
  List<DownloadCollection> get _collections => downloadCollections(
    _jobs,
    query: _search.text,
    filter: _filter,
    release: _release,
  );

  @override
  void initState() {
    super.initState();
    _epoch = widget.store.profileEpoch;
    _updater = DownloadCollectionUpdater(widget.repository, widget.store)
      ..addListener(_changed);
    widget.store.addListener(_changed);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stopBatch = true;
    _timer?.cancel();
    _search.dispose();
    _ownedTvSearchFocus?.dispose();
    _ownedTvReturnFocus?.dispose();
    _ownedTvStopFocus?.dispose();
    _ownedTvBatchFocus?.dispose();
    _ownedTvContentFocus?.dispose();
    _tvTitle.dispose();
    for (final node in _tvFilterNodes.values) {
      node.dispose();
    }
    widget.store.removeListener(_changed);
    _updater.removeListener(_changed);
    _updater.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing || !_allowed) return;
    _refreshing = true;
    try {
      final jobs = await widget.repository.downloads();
      if (mounted && _allowed) {
        setState(() {
          _jobs = jobs;
          _selected.retainAll(jobs.map((job) => job.id));
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && _allowed) setState(() => _error = error.toString());
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _batch(String command, Iterable<DownloadJob> source) async {
    if (_busy || !_allowed) return;
    final jobs = source
        .where(
          (job) => switch (command) {
            'pause' => job.active,
            'resume' => job.resumable,
            'archive' => job.completed && !job.archived,
            'restore' => job.completed && job.archived,
            'remove' => true,
            _ => false,
          },
        )
        .toList();
    if (jobs.isEmpty) {
      _message('没有适合此操作的任务');
      return;
    }
    if (command == 'remove') {
      final completed = jobs.where((job) => job.completed).length;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(completed > 0 ? '删除所选视频？' : '取消所选下载？'),
          content: Text(
            '共 ${jobs.length} 项${completed > 0 ? '，包含 $completed 个已下载视频' : ''}，文件也会删除。\n需要保留视频时，请选择“清理任务，保留视频”。',
          ),
          actions: [
            TextButton(
              autofocus: AppLayout.isTelevision(context),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认删除'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted || !_allowed) return;
    }
    setState(() {
      _busy = true;
      _stopBatch = false;
      _retryCommand = null;
    });
    if (AppLayout.isTelevision(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _busy) _tvStopFocus.requestFocus();
      });
    }
    final failures = <String, String>{};
    var completed = 0;
    try {
      for (var offset = 0; offset < jobs.length; offset += 500) {
        if (!mounted || !_allowed || _stopBatch) break;
        setState(
          () => _operation =
              '正在处理 ${math.min(offset + 500, jobs.length)}/${jobs.length} 项',
        );
        final ids = jobs
            .sublist(offset, math.min(offset + 500, jobs.length))
            .map((job) => job.id)
            .toList();
        try {
          final result = await widget.repository.controlDownloadBatch(
            command,
            ids,
          );
          if (!mounted || !_allowed) return;
          completed += result.completed.length;
          _selected.removeAll(result.completed);
          failures.addAll(result.failures);
        } catch (error) {
          failures.addAll({for (final id in ids) id: error.toString()});
        }
      }
      if (!mounted || !_allowed) return;
      if (failures.isNotEmpty) {
        _selected.addAll(failures.keys);
        _selecting = true;
        _retryCommand = command;
        _message(
          '已处理 $completed 项，${failures.length} 项失败：${failures.values.first}',
        );
      } else {
        _message(
          _stopBatch
              ? '已停止，已处理 $completed 项'
              : command == 'archive'
              ? '已清理 $completed 项任务，视频仍可本地播放'
              : '已处理 $completed 项',
        );
      }
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _operation = '';
        });
      }
    }
  }

  Future<void> _update(Drama drama) async {
    await _updater.update(drama);
    if (mounted && _allowed) {
      _message(_updater.error ?? _updater.status);
      await _refresh();
    }
  }

  Future<void> _play(DownloadJob job) async {
    if (_opening || !_allowed) return;
    _opening = true;
    final completed =
        _jobs
            .where((entry) => entry.completed && entry.drama.id == job.drama.id)
            .toList()
          ..sort((a, b) => a.episode.number.compareTo(b.episode.number));
    final index = completed.indexWhere((entry) => entry.id == job.id);
    if (index < 0) {
      _opening = false;
      return;
    }
    final detail = DramaDetail(
      job.drama,
      completed.map((entry) => entry.episode).toList(),
    );
    final watch = widget.store.watched(job.drama.id);
    final position = watch?.episode == job.episode.number && !watch!.finished
        ? watch.position
        : 0.0;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.playerBuilder?.call(detail, index, position) ??
              PlayerScreen(
                detail: detail,
                initialIndex: index,
                initialPosition: position,
                repository: widget.repository,
                store: widget.store,
                localOnly: true,
              ),
        ),
      );
    } finally {
      _opening = false;
      if (mounted) await _refresh();
    }
  }

  void _select(Iterable<DownloadJob> jobs) {
    final ids = jobs.map((job) => job.id).toSet();
    setState(() {
      _selecting = true;
      if (ids.every(_selected.contains)) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  Future<void> _filters() async {
    var state = _filter, release = _release;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: const Text('筛选下载合集'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('任务状态'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in const {
                        'all': '全部任务',
                        'pending': '未完成',
                        'active': '进行中',
                        'paused': '已暂停',
                        'failed': '失败',
                        'completed': '已下载',
                        'archived': '已保留视频',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: state == entry.key,
                          onSelected: (_) => change(() => state = entry.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('剧集状态'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in const {
                        '': '全部',
                        'ongoing': '连载中',
                        'finished': '已完结',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: release == entry.key,
                          onSelected: (_) => change(() => release = entry.key),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() {
        _filter = state;
        _release = release;
      });
    }
  }

  List<Widget> _titleActions(List<DownloadCollection> collections) => [
    if (_selecting) ...[
      IconButton(
        tooltip: '全选当前',
        onPressed: _busy
            ? null
            : () => _select(collections.expand((c) => c.jobs)),
        icon: const Icon(Icons.select_all_rounded),
      ),
      IconButton(
        tooltip: '退出多选',
        onPressed: _busy
            ? null
            : () => setState(() {
                _selecting = false;
                _selected.clear();
                _retryCommand = null;
              }),
        icon: const Icon(Icons.close_rounded),
      ),
    ] else ...[
      IconButton(
        tooltip: '筛选下载合集',
        onPressed: _filters,
        icon: Badge(
          isLabelVisible: _filter != 'all' || _release.isNotEmpty,
          child: const Icon(Icons.filter_list_rounded),
        ),
      ),
      IconButton(
        tooltip: '多选下载任务',
        onPressed: () => setState(() => _selecting = true),
        icon: const Icon(Icons.checklist_rounded),
      ),
      IconButton(
        key: const ValueKey('download-local-media'),
        tooltip: '本地媒体与合并',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => LocalMediaScreen(
              repository: widget.repository,
              store: widget.store,
            ),
          ),
        ),
        icon: const Icon(Icons.video_library_outlined),
      ),
    ],
    PopupMenuButton<String>(
      key: const ValueKey('download-queue-actions'),
      tooltip: '队列操作',
      enabled: !_busy,
      onSelected: (value) {
        if (value == 'refresh') {
          _refresh();
        } else {
          _batch(value, _jobs);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'pause', child: Text('全部暂停')),
        PopupMenuItem(value: 'resume', child: Text('全部继续')),
        PopupMenuItem(value: 'archive', child: Text('清理已完成任务，保留视频')),
        PopupMenuItem(value: 'refresh', child: Text('刷新记录')),
      ],
    ),
  ];

  Widget _collection(DownloadCollection collection) {
    final count = collection.jobs
        .where((job) => _selected.contains(job.id))
        .length;
    final expanded = _expanded.contains(collection.drama.id);
    return Card(
      child: ListTile(
        leading: _selecting
            ? Checkbox(
                tristate: true,
                value: count == 0
                    ? false
                    : count == collection.jobs.length
                    ? true
                    : null,
                onChanged: _busy ? null : (_) => _select(collection.jobs),
              )
            : Icon(expanded ? Icons.folder_open_rounded : Icons.folder_rounded),
        title: Text(
          collection.drama.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${collection.completed}/${collection.jobs.length} 集已下载 · ${storageSize(collection.bytes)}'
          '${collection.active > 0 ? ' · ${collection.active} 项进行中' : ''}${collection.failed > 0 ? ' · ${collection.failed} 项失败' : ''}',
        ),
        onTap: () => setState(() {
          if (!_expanded.remove(collection.drama.id)) {
            _expanded.add(collection.drama.id);
          }
        }),
        trailing: PopupMenuButton<String>(
          tooltip: '${collection.drama.title} · 合集操作',
          enabled: !_busy,
          onSelected: (value) {
            if (value == 'update') {
              _update(collection.drama);
            } else if (value == 'select') {
              _select(collection.jobs);
            } else {
              _batch(value, collection.jobs);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'update',
              enabled: !_updater.busy,
              child: const Text('更新本剧 · 补充新增与缺失'),
            ),
            const PopupMenuItem(value: 'select', child: Text('选择本合集')),
            const PopupMenuItem(value: 'pause', child: Text('暂停本合集')),
            const PopupMenuItem(value: 'resume', child: Text('继续 / 重试本合集')),
            const PopupMenuItem(value: 'archive', child: Text('清理已完成任务，保留视频')),
            if (_filter == 'archived')
              const PopupMenuItem(value: 'restore', child: Text('恢复到任务列表')),
            const PopupMenuItem(value: 'remove', child: Text('取消任务并删除视频')),
          ],
        ),
      ),
    );
  }

  Widget _episode(DownloadJob job) => Padding(
    padding: const EdgeInsets.only(left: 12),
    child: Card(
      key: ValueKey('download-task-${job.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: _selecting
                ? Checkbox(
                    value: _selected.contains(job.id),
                    onChanged: _busy ? null : (_) => _select([job]),
                  )
                : Icon(
                    job.completed
                        ? Icons.offline_pin_outlined
                        : job.state == 'failed'
                        ? Icons.error_outline
                        : Icons.downloading_rounded,
                  ),
            title: Text(
              '第 ${job.episode.number} 集${job.episode.vip ? ' · VIP' : ''}',
            ),
            subtitle: Text(
              '${job.archived ? '已保留视频' : job.stateLabel} · ${storageSize(job.bytes)}'
              '${job.actualQuality > 0 ? ' · ${job.actualQuality}P' : ''}${job.error.isNotEmpty ? '\n${job.error}' : ''}',
            ),
            onTap: _busy
                ? null
                : _selecting
                ? () => _select([job])
                : job.completed
                ? () => _play(job)
                : null,
            trailing: _selecting
                ? null
                : PopupMenuButton<String>(
                    enabled: !_busy,
                    tooltip: '分集操作',
                    onSelected: (value) {
                      if (value == 'play') {
                        _play(job);
                      } else {
                        _batch(value, [job]);
                      }
                    },
                    itemBuilder: (_) => [
                      if (job.completed)
                        const PopupMenuItem(value: 'play', child: Text('本地播放')),
                      if (job.active)
                        const PopupMenuItem(value: 'pause', child: Text('暂停')),
                      if (job.resumable)
                        const PopupMenuItem(
                          value: 'resume',
                          child: Text('继续 / 重试'),
                        ),
                      if (job.completed)
                        PopupMenuItem(
                          value: job.archived ? 'restore' : 'archive',
                          child: Text(job.archived ? '恢复任务' : '清理任务，保留视频'),
                        ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(job.completed ? '删除视频' : '取消下载'),
                      ),
                    ],
                  ),
          ),
          if (!job.completed)
            LinearProgressIndicator(
              value: job.progress > 0 || !job.active ? job.progress : null,
              minHeight: 2,
            ),
        ],
      ),
    ),
  );

  Widget _batchBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            if (_busy)
              TextButton(
                onPressed: () => setState(() => _stopBatch = true),
                child: const Text('停止批量操作'),
              )
            else ...[
              for (final entry in const {
                'pause': '暂停',
                'resume': '继续 / 重试',
                'archive': '保留视频',
                'remove': '删除',
              }.entries)
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _batch(
                          entry.key,
                          _jobs.where((job) => _selected.contains(job.id)),
                        ),
                  child: Text(entry.value),
                ),
              if (_retryCommand != null)
                FilledButton(
                  onPressed: () => _batch(
                    _retryCommand!,
                    _jobs.where((job) => _selected.contains(job.id)),
                  ),
                  child: const Text('重试失败项'),
                ),
            ],
          ],
        ),
      ),
    ),
  );

  static const _tvStates = {
    'all': '全部',
    'pending': '未完成',
    'active': '进行中',
    'paused': '已暂停',
    'failed': '失败',
    'completed': '已下载',
    'archived': '保留视频',
  };

  Future<String?> _tvMenu(String title, List<(String, String)> choices) =>
      showDialog<String>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 620,
            height: math.min(600, MediaQuery.sizeOf(context).height * .8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭操作菜单',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: RemoteGrid(
                      itemKeys: choices.map((entry) => entry.$1).toList(),
                      columns: 1,
                      itemExtent: math.max(
                        64,
                        MediaQuery.textScalerOf(
                                  context,
                                ).scale(TelevisionStyle.body) *
                                2.6 +
                            28,
                      ),
                      autofocus: true,
                      padding: const EdgeInsets.all(4),
                      spacing: 8,
                      itemBuilder: (_, index, node, onFocus) => RemoteButton(
                        key: ValueKey(
                          'tv-download-action-${choices[index].$1}',
                        ),
                        label: choices[index].$2,
                        maxLines: 2,
                        focusNode: node,
                        onFocus: onFocus,
                        onPressed: () =>
                            Navigator.pop(context, choices[index].$1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  void _restoreTvFocus(FocusNode? node) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (node?.context != null) {
      node!.requestFocus();
    } else if (_tvCollectionId != null) {
      _tvReturnFocus.requestFocus();
    } else {
      _tvSearchFocus.requestFocus();
    }
  }

  Future<void> _tvCollectionActions(
    DownloadCollection collection,
    FocusNode node,
  ) async {
    if (_busy) return;
    try {
      final command = await _tvMenu(collection.drama.title, [
        if (!_updater.busy) ('update', '更新本剧 · 补充新增与缺失'),
        ('select', '选择本合集'),
        if (collection.jobs.any((job) => job.active)) ('pause', '暂停本合集'),
        if (collection.jobs.any((job) => job.resumable))
          ('resume', '继续 / 重试本合集'),
        if (collection.jobs.any((job) => job.completed && !job.archived))
          ('archive', '清理已完成任务，保留视频'),
        if (collection.jobs.any((job) => job.archived)) ('restore', '恢复到任务列表'),
        ('remove', '取消任务并删除视频'),
      ]);
      if (!mounted || !_allowed || command == null) return;
      final jobs = _jobs
          .where((job) => job.drama.id == collection.drama.id)
          .toList();
      if (command == 'update') {
        await _update(collection.drama);
      } else if (command == 'select') {
        _select(jobs);
      } else {
        await _batch(command, jobs);
      }
    } finally {
      _restoreTvFocus(node);
    }
  }

  Future<void> _tvEpisodeActions(DownloadJob job, FocusNode node) async {
    if (_busy) return;
    try {
      final command =
          await _tvMenu('${job.drama.title} · 第 ${job.episode.number} 集', [
            if (job.completed) ('play', '本地播放'),
            if (job.active) ('pause', '暂停下载'),
            if (job.resumable) ('resume', '继续 / 重试下载'),
            ('select', '选择此集'),
            if (job.error.isNotEmpty) ('error', '查看失败原因'),
            if (job.completed)
              (
                job.archived ? 'restore' : 'archive',
                job.archived ? '恢复到任务列表' : '清理任务，保留视频',
              ),
            ('remove', job.completed ? '删除视频' : '取消下载'),
          ]);
      if (!mounted || !_allowed || command == null) return;
      final fresh = _jobs.where((entry) => entry.id == job.id).firstOrNull;
      if (fresh == null) return;
      if (command == 'play') {
        await _play(fresh);
      } else if (command == 'select') {
        _select([fresh]);
      } else if (command == 'error') {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('下载失败原因'),
            content: Text(fresh.error),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      } else {
        await _batch(command, [fresh]);
      }
    } finally {
      _restoreTvFocus(node);
    }
  }

  Future<void> _tvToolbarActions(List<DownloadCollection> collections) async {
    final command = await _tvMenu('下载管理', [
      ('filter', '筛选任务与剧集状态'),
      if (_selecting) ...[
        ('select-all', '全选当前结果'),
        ('exit-selection', '退出多选'),
      ] else
        ('select', '多选下载任务'),
      ('local', '本地媒体与合并'),
      ('pause', '全部暂停'),
      ('resume', '全部继续 / 重试'),
      ('archive', '清理已完成任务，保留视频'),
      ('refresh', '刷新记录'),
    ]);
    if (!mounted || !_allowed || command == null) return;
    if (command == 'filter') {
      await _filters();
      if (!mounted || !_allowed) return;
      setState(() => _tvCollectionId = null);
    } else if (command == 'select') {
      setState(() => _selecting = true);
    } else if (command == 'select-all') {
      _select(collections.expand((collection) => collection.jobs));
    } else if (command == 'exit-selection') {
      _exitSelection();
    } else if (command == 'local') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => LocalMediaScreen(
            repository: widget.repository,
            store: widget.store,
          ),
        ),
      );
    } else if (command == 'refresh') {
      await _refresh();
    } else {
      await _batch(command, _jobs);
    }
    _restoreTvFocus(_ownedTvSearchFocus ?? widget.searchFocusNode);
  }

  Future<void> _tvBatchActions() async {
    final command = await _tvMenu('已选 ${_selected.length} 项', [
      ('pause', '暂停所选'),
      ('resume', '继续 / 重试所选'),
      ('archive', '清理所选任务，保留视频'),
      ('remove', '取消所选任务并删除视频'),
      if (_retryCommand != null) ('retry', '重试失败项'),
    ]);
    if (!mounted || !_allowed || command == null) return;
    await _batch(
      command == 'retry' ? _retryCommand! : command,
      _jobs.where((job) => _selected.contains(job.id)),
    );
    _restoreTvFocus(_ownedTvSearchFocus ?? widget.searchFocusNode);
  }

  Widget _tvDownloadCard({
    required String id,
    required String title,
    required String summary,
    required String status,
    required String action,
    required double progress,
    required IconData icon,
    required FocusNode node,
    required VoidCallback onFocus,
    required VoidCallback? onPressed,
    required VoidCallback onMore,
    bool selected = false,
    bool error = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.contextMenu,
          includeRepeats: false,
        ): onMore,
      },
      child: RemoteTarget(
        key: ValueKey(id),
        focusNode: node,
        onFocus: () {
          onFocus();
          _tvTitle.value = title;
        },
        selected: selected,
        focusScale: 1.02,
        onPressed: onPressed,
        onLongPress: onMore,
        label: '$title，$status，$summary',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      selected ? Icons.check_circle_rounded : icon,
                      size: 34,
                      color: error ? colors.error : colors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TelevisionStyle.body,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TelevisionStyle.secondary,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TelevisionStyle.secondary,
                    color: error ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                ),
                const SizedBox(height: 8),
                Text(
                  action,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TelevisionStyle.secondary,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _televisionDownloads() {
    final colors = Theme.of(context).colorScheme;
    final collections = _collections;
    final current = _tvCollectionId == null
        ? null
        : collections
              .where((collection) => collection.drama.id == _tvCollectionId)
              .firstOrNull;
    final opened = _tvCollectionId != null;
    final jobs = current?.jobs ?? const <DownloadJob>[];
    final counts = <String, int>{for (final id in _tvStates.keys) id: 0};
    for (final job in _jobs) {
      if (job.archived) {
        counts['archived'] = counts['archived']! + 1;
        continue;
      }
      counts['all'] = counts['all']! + 1;
      if (!job.completed) counts['pending'] = counts['pending']! + 1;
      if (job.active) counts['active'] = counts['active']! + 1;
      if (counts.containsKey(job.state)) {
        counts[job.state] = counts[job.state]! + 1;
      }
    }
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (!(const [
          LogicalKeyboardKey.escape,
          LogicalKeyboardKey.goBack,
          LogicalKeyboardKey.browserBack,
        ]).contains(event.logicalKey)) {
          return KeyEventResult.ignored;
        }
        if (event is KeyRepeatEvent) return KeyEventResult.handled;
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (handleTelevisionBack()) return KeyEventResult.handled;
        if (!widget.embedded) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: SizedBox(
            height: math.max(380, constraints.maxHeight),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Focus(
                    canRequestFocus: false,
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                          widget.onSearchUp != null) {
                        widget.onSearchUp!();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        _focusTvContent();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Row(
                      children: [
                        if (opened) ...[
                          RemoteButton(
                            key: const ValueKey('tv-download-back-collections'),
                            label: '合集',
                            focusNode: _tvReturnFocus,
                            icon: Icons.arrow_back_rounded,
                            onPressed: _closeTvCollection,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current?.drama.title ??
                                    (opened ? '分集记录' : '下载合集'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                _selecting
                                    ? '已选 ${_selected.length} 项'
                                    : opened
                                    ? '${jobs.length} 集 · 确认播放或管理'
                                    : '${collections.length} 部 · ${collections.fold<int>(0, (sum, collection) => sum + collection.jobs.length)} 集',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: (constraints.maxWidth * .28).clamp(
                            220.0,
                            300.0,
                          ),
                          child: AdaptiveTextField(
                            key: const ValueKey('downloads-search'),
                            controller: _search,
                            focusNode: _tvSearchFocus,
                            onChanged: (_) =>
                                setState(() => _tvCollectionId = null),
                            textInputAction: TextInputAction.search,
                            decoration: const InputDecoration(
                              hintText: '搜索下载',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        RemoteButton(
                          key: const ValueKey('tv-download-tools'),
                          label: '更多',
                          icon: Icons.more_horiz_rounded,
                          onPressed: _busy
                              ? null
                              : () => _tvToolbarActions(collections),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 196,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Focus(
                            canRequestFocus: false,
                            onKeyEvent: (_, event) {
                              if (event is! KeyDownEvent &&
                                  event is! KeyRepeatEvent) {
                                return KeyEventResult.ignored;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight) {
                                _focusTvContent();
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowUp &&
                                  _tvFilterFocus('all').hasFocus) {
                                _tvSearchFocus.requestFocus();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: ListView(
                              padding: const EdgeInsets.all(4),
                              children: [
                                for (final entry in _tvStates.entries)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: RemoteTarget(
                                      key: ValueKey(
                                        'tv-download-filter-${entry.key}',
                                      ),
                                      focusNode: _tvFilterFocus(entry.key),
                                      selected: _filter == entry.key,
                                      label:
                                          '${entry.value}，${counts[entry.key]}项任务',
                                      onPressed: () => setState(() {
                                        _filter = entry.key;
                                        _tvCollectionId = null;
                                      }),
                                      child: SizedBox(
                                        height: 42,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  entry.value,
                                                  style: const TextStyle(
                                                    fontSize:
                                                        TelevisionStyle.body,
                                                    height: 1.2,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '${counts[entry.key]}',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                              if (_filter == entry.key) ...[
                                                const SizedBox(width: 6),
                                                Icon(
                                                  Icons.check_rounded,
                                                  size: 18,
                                                  color: colors.primary,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FocusScope(
                          node: _tvContentFocus,
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _error != null && _jobs.isEmpty
                              ? StatusPanel(
                                  title: '无法读取下载记录',
                                  message: _error!,
                                  onRetry: _refresh,
                                )
                              : collections.isEmpty || opened && jobs.isEmpty
                              ? StatusPanel(
                                  title: opened
                                      ? '暂无符合条件的分集'
                                      : _jobs.isEmpty
                                      ? '还没有下载任务'
                                      : '暂无符合条件的任务',
                                  message: '选择左侧其他状态，或在剧集详情选择下载。',
                                  icon: Icons.download_outlined,
                                  secondaryAction: _search.text.isEmpty
                                      ? null
                                      : RemoteButton(
                                          label: '清除搜索',
                                          onPressed: () {
                                            setState(() {
                                              _search.clear();
                                              _tvCollectionId = null;
                                            });
                                            _tvSearchFocus.requestFocus();
                                          },
                                        ),
                                )
                              : LayoutBuilder(
                                  builder: (context, grid) {
                                    final scale = MediaQuery.textScalerOf(
                                      context,
                                    );
                                    final extent = math.max(
                                      210.0,
                                      scale.scale(TelevisionStyle.body) * 2.6 +
                                          scale.scale(
                                                TelevisionStyle.secondary,
                                              ) *
                                              4.5 +
                                          78,
                                    );
                                    return RemoteGrid(
                                      key: ValueKey(
                                        'tv-download-${opened ? _tvCollectionId : 'collections'}-$_filter-$_release-${_search.text}',
                                      ),
                                      itemKeys: opened
                                          ? jobs.map((job) => job.id).toList()
                                          : collections
                                                .map(
                                                  (collection) =>
                                                      collection.drama.id,
                                                )
                                                .toList(),
                                      columns: grid.maxWidth >= 600 ? 2 : 1,
                                      itemExtent: extent,
                                      spacing: 16,
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        8,
                                        12,
                                        16,
                                      ),
                                      onLeft: () => _tvFilterFocus(
                                        _filter,
                                      ).requestFocus(),
                                      onUp: opened
                                          ? _tvReturnFocus.requestFocus
                                          : _tvSearchFocus.requestFocus,
                                      onDown: _busy || _updater.busy
                                          ? _tvStopFocus.requestFocus
                                          : _selecting && _selected.isNotEmpty
                                          ? _tvBatchFocus.requestFocus
                                          : null,
                                      itemBuilder: (_, index, node, onFocus) {
                                        if (opened) {
                                          final job = jobs[index];
                                          return _tvDownloadCard(
                                            id: 'download-task-${job.id}',
                                            title:
                                                '第 ${job.episode.number} 集${job.episode.vip ? ' · VIP' : ''}',
                                            summary:
                                                '${storageSize(job.bytes)}${job.total > 0 ? ' / ${storageSize(job.total)}' : ''}${job.actualQuality > 0 ? ' · ${job.actualQuality}P' : ''}',
                                            status: job.archived
                                                ? '已保留视频'
                                                : job.error.isNotEmpty
                                                ? '${job.stateLabel} · ${job.error}'
                                                : job.stateLabel,
                                            action: _selecting
                                                ? '确认选择此集'
                                                : job.completed
                                                ? '确认本地播放 · 长按更多'
                                                : '确认管理下载',
                                            progress: job.completed
                                                ? 1
                                                : job.progress,
                                            icon: job.completed
                                                ? Icons.offline_pin_outlined
                                                : Icons.downloading_rounded,
                                            node: node,
                                            onFocus: onFocus,
                                            selected: _selected.contains(
                                              job.id,
                                            ),
                                            error: job.state == 'failed',
                                            onPressed: _busy
                                                ? null
                                                : () async {
                                                    if (_selecting) {
                                                      _select([job]);
                                                    } else if (job.completed) {
                                                      await _play(job);
                                                      _restoreTvFocus(node);
                                                    } else {
                                                      await _tvEpisodeActions(
                                                        job,
                                                        node,
                                                      );
                                                    }
                                                  },
                                            onMore: () =>
                                                _tvEpisodeActions(job, node),
                                          );
                                        }
                                        final collection = collections[index];
                                        final count = collection.jobs
                                            .where(
                                              (job) =>
                                                  _selected.contains(job.id),
                                            )
                                            .length;
                                        final completed = collection.completed,
                                            active = collection.active,
                                            failed = collection.failed;
                                        return _tvDownloadCard(
                                          id: 'tv-download-collection-${collection.drama.id}',
                                          title: collection.drama.title,
                                          summary:
                                              '$completed/${collection.jobs.length} 集已下载 · ${storageSize(collection.bytes)}',
                                          status: _selecting
                                              ? '$count/${collection.jobs.length} 项已选'
                                              : '$active 项进行中 · $failed 项失败',
                                          action: _selecting
                                              ? '确认选择本合集'
                                              : '确认查看分集 · 长按更多',
                                          progress: collection.jobs.isEmpty
                                              ? 0
                                              : completed /
                                                    collection.jobs.length,
                                          icon: Icons.folder_rounded,
                                          node: node,
                                          onFocus: onFocus,
                                          selected: count > 0,
                                          error: failed > 0,
                                          onPressed: _busy
                                              ? null
                                              : () {
                                                  if (_selecting) {
                                                    _select(collection.jobs);
                                                  } else {
                                                    setState(
                                                      () => _tvCollectionId =
                                                          collection.drama.id,
                                                    );
                                                    WidgetsBinding.instance
                                                        .addPostFrameCallback((
                                                          _,
                                                        ) {
                                                          if (mounted) {
                                                            _focusTvContent();
                                                          }
                                                        });
                                                  }
                                                },
                                          onMore: () => _tvCollectionActions(
                                            collection,
                                            node,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Focus(
                    canRequestFocus: false,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _focusTvContent();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<String>(
                            valueListenable: _tvTitle,
                            builder: (context, title, _) => Text(
                              _busy
                                  ? _operation
                                  : _updater.busy
                                  ? _updater.status
                                  : _error ??
                                        '${title.isEmpty ? '' : '$title · '}确认进入 / 播放 · 长按确认更多 · 返回回到上层',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                        if (_busy || _updater.busy)
                          RemoteButton(
                            key: const ValueKey('tv-download-stop'),
                            focusNode: _tvStopFocus,
                            label: _busy ? '停止批量操作' : '停止更新',
                            onPressed: _busy
                                ? () => setState(() => _stopBatch = true)
                                : _updater.cancel,
                          )
                        else if (_selecting)
                          RemoteButton(
                            key: const ValueKey('tv-download-batch'),
                            focusNode: _tvBatchFocus,
                            label: '已选 ${_selected.length} · 批量操作',
                            onPressed: _selected.isEmpty
                                ? null
                                : _tvBatchActions,
                          ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const StatusPanel(title: '当前用户无权访问下载', message: '请返回后重新操作。');
    }
    if (AppLayout.isTelevision(context)) {
      final content = _televisionDownloads();
      if (widget.embedded) return content;
      return PopScope(
        canPop: !_selecting && _tvCollectionId == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) handleTelevisionBack();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('下载管理')),
          body: TelevisionPageBody(child: content),
        ),
      );
    }
    final collections = _collections;
    final rows = <Object>[
      for (final collection in collections) ...[
        collection,
        if (_expanded.contains(collection.drama.id)) ...collection.jobs,
      ],
    ];
    final title = _selecting ? '已选 ${_selected.length} 项' : '下载合集';
    final actions = _titleActions(collections);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: AdaptiveTextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索剧名、站源或分类',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Text(
            '${collections.length} 部 · ${collections.fold<int>(0, (sum, c) => sum + c.jobs.length)} 集'
            '${_filter == 'archived' ? ' · 已清理任务，视频仍保留' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_updater.busy || _busy) LinearProgressIndicator(minHeight: 2),
        if (_updater.busy || _busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _busy ? _operation : _updater.status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_updater.busy)
                  TextButton(
                    onPressed: _updater.cancel,
                    child: const Text('停止'),
                  ),
              ],
            ),
          ),
        if (_error != null && _jobs.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _jobs.isEmpty
              ? StatusPanel(
                  title: '无法读取下载记录',
                  message: _error!,
                  onRetry: _refresh,
                )
              : rows.isEmpty
              ? StatusPanel(
                  title: _jobs.isEmpty ? '还没有下载任务' : '暂无符合条件的任务',
                  message: '在剧集详情选择下载，或调整筛选查看已保留的视频。',
                  icon: Icons.download_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: rows.length,
                  itemBuilder: (_, index) => switch (rows[index]) {
                    DownloadCollection collection => _collection(collection),
                    DownloadJob job => _episode(job),
                    _ => const SizedBox.shrink(),
                  },
                ),
        ),
        if (_selecting) _batchBar(),
      ],
    );
    if (widget.embedded) return body;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.goBack): () =>
            Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: TelevisionPageBody(child: SafeArea(top: false, child: body)),
      ),
    );
  }
}
