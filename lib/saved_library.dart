import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_layout.dart';
import 'adaptive_text_field.dart';
import 'catalog_sort.dart';
import 'core_bridge.dart';
import 'drama_actions.dart';
import 'follow_state.dart';
import 'local_store.dart';
import 'models.dart';
import 'remote_widgets.dart';
import 'widgets.dart';

class SavedLibrary extends StatefulWidget {
  const SavedLibrary({
    super.key,
    required this.repository,
    required this.store,
    required this.history,
    required this.onOpen,
    required this.onContinue,
    this.onDownload,
    this.searchFocusNode,
    this.onSearchUp,
    this.initialFilter = '',
  });

  final AppRepository repository;
  final LocalStore store;
  final bool history;
  final FutureOr<void> Function(Drama) onOpen;
  final FutureOr<void> Function(Drama) onContinue;
  final ValueChanged<Drama>? onDownload;
  final FocusNode? searchFocusNode;
  final VoidCallback? onSearchUp;
  final String initialFilter;

  @override
  State<SavedLibrary> createState() => _SavedLibraryState();
}

class _SavedLibraryState extends State<SavedLibrary> {
  final _search = TextEditingController();
  late String _filter = widget.initialFilter;
  FocusNode? _ownedSearchFocus;
  FocusScopeNode? _ownedContentFocus;
  FocusScopeNode get _contentFocus =>
      _ownedContentFocus ??= FocusScopeNode(debugLabel: 'tv-library-content');
  final _filterNodes = <String, FocusNode>{};
  ValueNotifier<Drama?>? _selectionNotifier;
  ValueNotifier<Drama?> get _focusedDrama =>
      _selectionNotifier ??= ValueNotifier(null);
  FocusNode get _searchFocus =>
      widget.searchFocusNode ??
      (_ownedSearchFocus ??= FocusNode(debugLabel: 'tv-library-search'));
  FocusNode _filterFocus(String id) => _filterNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'tv-library-filter-$id'),
  );

  bool _canContinue(WatchEntry entry) =>
      !entry.finished ||
      entry.drama.episodes <= 0 ||
      entry.episode < entry.drama.episodes;

  void _focusContent() {
    if (_contentFocus.context == null ||
        !_contentFocus.traversalDescendants.any(
          (node) => node.canRequestFocus,
        )) {
      _filterFocus(_filter).requestFocus();
      return;
    }
    final previous = _contentFocus.focusedChild;
    _contentFocus.requestFocus();
    if (previous == null) _contentFocus.nextFocus();
  }

  Future<void> _activate(Drama drama, FocusNode node) async {
    try {
      if (widget.history) {
        await widget.onContinue(drama);
      } else {
        await widget.onOpen(drama);
      }
    } finally {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        if (node.context != null) {
          node.requestFocus();
        } else {
          _searchFocus.requestFocus();
        }
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _ownedSearchFocus?.dispose();
    _ownedContentFocus?.dispose();
    _selectionNotifier?.dispose();
    for (final node in _filterNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _clearHistory() async {
    final epoch = widget.store.profileEpoch;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空观看记录？'),
        content: const Text('这会删除当前用户的观看进度，追剧状态和手动已看标记会保留。'),
        actions: [
          TextButton(
            autofocus: AppLayout.isTelevision(context),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && epoch == widget.store.profileEpoch) {
      await saveUserChange(context, widget.store.clearHistory);
      if (mounted && AppLayout.isTelevision(context)) {
        _searchFocus.requestFocus();
      }
    }
  }

  Future<void> _actions(Drama drama, {FocusNode? returnFocus}) async {
    await showDramaActions(
      context,
      drama: drama,
      store: widget.store,
      repository: widget.repository,
      history: widget.history,
      onContinue: () => widget.onContinue(drama),
      onDownload: widget.onDownload == null
          ? null
          : () => widget.onDownload!(drama),
    );
    if (mounted &&
        AppLayout.isTelevision(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      if (returnFocus?.context != null) {
        returnFocus!.requestFocus();
      } else {
        _filterFocus(_filter).requestFocus();
      }
    }
  }

  Widget _tile(Drama drama, {FocusNode? focusNode, VoidCallback? onFocus}) {
    final watched = widget.store.watched(drama.id);
    final state = widget.store.following(drama.id);
    final badge = state == null
        ? null
        : '${state.label}${state.hasUpdates ? ' · ${state.updateLabel}' : ''}';
    return DramaTile(
      key: ValueKey('saved-${drama.id}'),
      drama: drama,
      repository: widget.repository,
      focusNode: focusNode,
      onFocus: onFocus,
      onTap: () => widget.onOpen(drama),
      onMore: () => _actions(drama),
      actions: DramaActionButton(
        drama: drama,
        onPressed: () => _actions(drama),
      ),
      badge: badge,
      subtitle: watched == null
          ? SourceSite.byId(drama.source).name
          : '第 ${watched.episode} 集 · ${formatPosition(watched.position)}',
    );
  }

  Widget _televisionLibrary(List<Drama> all, List<Drama> items) {
    final colors = Theme.of(context).colorScheme;
    final filters = widget.history
        ? const [('', '全部'), ('continue', '可续播'), ('finished', '已看完')]
        : const [
            ('', '全部'),
            ('updates', '有更新'),
            ('watching', '在看'),
            ('planned', '想看'),
            ('watched', '已看'),
          ];
    final counts = <String, int>{for (final filter in filters) filter.$1: 0};
    counts[''] = all.length;
    for (final drama in all) {
      if (widget.history) {
        final watched = widget.store.watched(drama.id);
        final id = watched != null && _canContinue(watched)
            ? 'continue'
            : 'finished';
        counts[id] = counts[id]! + 1;
      } else {
        final state = widget.store.following(drama.id);
        if (state?.hasUpdates == true) {
          counts['updates'] = counts['updates']! + 1;
        }
        final id = state?.status.name;
        if (id != null && counts.containsKey(id)) counts[id] = counts[id]! + 1;
      }
    }
    final empty = StatusPanel(
      title: all.isEmpty
          ? widget.history
                ? '还没有观看记录'
                : '还没有追剧'
          : '没有匹配的记录',
      message: all.isEmpty ? '到发现页选择喜欢的剧，观看或加入追剧后会显示在这里。' : '换个搜索词，或选择左侧其他分类。',
      icon: widget.history
          ? Icons.history_rounded
          : Icons.bookmark_border_rounded,
      secondaryAction: _search.text.isEmpty
          ? null
          : RemoteButton(
              label: '清除搜索',
              onPressed: () {
                setState(_search.clear);
                _searchFocus.requestFocus();
              },
            ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SizedBox(
          height: math.max(360, constraints.maxHeight),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Icon(
                      widget.history
                          ? Icons.history_rounded
                          : Icons.bookmark_rounded,
                      size: 30,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.history ? '最近观看' : '我的追剧',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            _search.text.isEmpty
                                ? '${all.length} 部 · ${widget.history ? '按最近播放排序' : '按加入追剧排序'}'
                                : '${items.length} 部匹配 · 共 ${all.length} 部',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: (constraints.maxWidth * .32).clamp(220.0, 320.0),
                      child: Focus(
                        canRequestFocus: false,
                        onKeyEvent: (_, event) {
                          if (event is! KeyDownEvent &&
                              event is! KeyRepeatEvent) {
                            return KeyEventResult.ignored;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                              widget.onSearchUp != null) {
                            widget.onSearchUp!();
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey ==
                              LogicalKeyboardKey.arrowDown) {
                            _focusContent();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: AdaptiveTextField(
                          key: ValueKey(
                            widget.history
                                ? 'history-search'
                                : 'favorites-search',
                          ),
                          controller: _search,
                          focusNode: _searchFocus,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: widget.history ? '搜索观看记录' : '搜索追剧',
                            prefixIcon: const Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                    ),
                    if (widget.history && all.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      RemoteButton(
                        key: const ValueKey('tv-clear-history'),
                        label: '清空',
                        icon: Icons.delete_outline_rounded,
                        onPressed: _clearHistory,
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: math.min(
                        240,
                        184 +
                            (MediaQuery.textScalerOf(
                                      context,
                                    ).scale(TelevisionStyle.body) -
                                    TelevisionStyle.body) *
                                3,
                      ),
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
                                    LogicalKeyboardKey.arrowRight &&
                                items.isNotEmpty) {
                              _focusContent();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp &&
                                _filterFocus(filters.first.$1).hasFocus) {
                              _searchFocus.requestFocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: ListView(
                            padding: const EdgeInsets.all(2),
                            children: [
                              for (final filter in filters)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: RemoteTarget(
                                    key: ValueKey(
                                      widget.history
                                          ? 'history-filter-${filter.$1}'
                                          : 'follow-filter-${filter.$1}',
                                    ),
                                    focusNode: _filterFocus(filter.$1),
                                    selected: _filter == filter.$1,
                                    label: '${filter.$2}，${counts[filter.$1]}部',
                                    onPressed: () => setState(() {
                                      _filter = filter.$1;
                                      _focusedDrama.value = null;
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: SizedBox(
                                        height: TelevisionStyle.target - 14,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                filter.$2,
                                                style: const TextStyle(
                                                  fontSize:
                                                      TelevisionStyle.body,
                                                  height: 1.2,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${counts[filter.$1]}',
                                              style: TextStyle(
                                                fontSize:
                                                    TelevisionStyle.secondary,
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                            if (_filter == filter.$1) ...[
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
                      child: items.isEmpty
                          ? empty
                          : FocusScope(
                              node: _contentFocus,
                              child: LayoutBuilder(
                                builder: (context, grid) {
                                  final scale = MediaQuery.textScalerOf(
                                    context,
                                  );
                                  final columns = grid.maxWidth >= 600 ? 2 : 1;
                                  final extent = math.max(
                                    200.0,
                                    scale.scale(TelevisionStyle.body) * 2.6 +
                                        scale.scale(TelevisionStyle.secondary) *
                                            4.5 +
                                        70,
                                  );
                                  return RemoteGrid(
                                    key: ValueKey(
                                      'saved-tv-${widget.history}-$_filter-${_search.text}',
                                    ),
                                    itemKeys: items
                                        .map((drama) => drama.id)
                                        .toList(),
                                    columns: columns,
                                    itemExtent: extent,
                                    spacing: 16,
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      12,
                                      16,
                                    ),
                                    onLeft: () =>
                                        _filterFocus(_filter).requestFocus(),
                                    onUp: _searchFocus.requestFocus,
                                    itemBuilder: (_, index, node, onFocus) =>
                                        _televisionTile(items[index], node, () {
                                          onFocus();
                                          _focusedDrama.value = items[index];
                                        }),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ValueListenableBuilder<Drama?>(
                    valueListenable: _focusedDrama,
                    builder: (context, selected, _) {
                      final focused = selected == null
                          ? null
                          : items
                                .where((drama) => drama.id == selected.id)
                                .firstOrNull;
                      return Text(
                        focused == null
                            ? '左右切换分类与内容 · 确认${widget.history ? '续播' : '播放'} · 长按确认更多'
                            : '${focused.title} · 确认${widget.history ? '续播' : '播放'} · 长按确认更多',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _televisionTile(Drama drama, FocusNode node, VoidCallback onFocus) {
    final watched = widget.store.watched(drama.id);
    final state = widget.store.following(drama.id);
    final colors = Theme.of(context).colorScheme;
    final continuing = watched != null && _canContinue(watched);
    final status = widget.history
        ? continuing
              ? '可继续观看'
              : '已看完'
        : state?.hasUpdates == true
        ? '${state!.label} · ${state.updateLabel}'
        : state?.label ?? '已追剧';
    final updated = !widget.history && state?.hasUpdates == true;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.contextMenu,
          includeRepeats: false,
        ): () =>
            _actions(drama, returnFocus: node),
      },
      child: RemoteTarget(
        key: ValueKey('saved-${drama.id}'),
        focusNode: node,
        onFocus: onFocus,
        focusScale: 1.02,
        onPressed: () => _activate(drama, node),
        onLongPress: () => _actions(drama, returnFocus: node),
        label:
            '${drama.title}，$status${watched == null ? '' : '，第 ${watched.episode} 集，${formatPosition(watched.position)}'}',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SizedBox(
                    width: 84,
                    height: 126,
                    child: DramaCover(
                      drama: drama,
                      repository: widget.repository,
                      radius: 10,
                      showEpisodeCount: false,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        drama.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TelevisionStyle.body,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${SourceSite.byId(drama.source).name} · ${drama.episodes > 0 ? '${drama.episodes} 集' : '集数待更新'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TelevisionStyle.secondary,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        widget.history && watched != null
                            ? watched.finished && continuing
                                  ? '第 ${watched.episode} 集已看完'
                                  : '第 ${watched.episode} 集 · ${formatPosition(watched.position)}${watched.duration > 0 ? ' / ${formatPosition(watched.duration)}' : ''}'
                            : status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TelevisionStyle.secondary,
                          fontWeight: updated
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: updated
                              ? colors.tertiary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (widget.history) ...[
                        LinearProgressIndicator(
                          value: watched == null || watched.duration <= 0
                              ? 0
                              : (watched.position / watched.duration).clamp(
                                  0.0,
                                  1.0,
                                ),
                          minHeight: 4,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Icon(
                            updated
                                ? Icons.notifications_active_outlined
                                : Icons.play_circle_outline_rounded,
                            size: 20,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.history
                                  ? !continuing
                                        ? '重新播放'
                                        : watched.finished &&
                                              drama.episodes > watched.episode
                                        ? '继续下一集'
                                        : '继续播放'
                                  : watched == null
                                  ? '开始观看'
                                  : _canContinue(watched)
                                  ? '继续观看'
                                  : '重新播放',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: TelevisionStyle.secondary,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final television = AppLayout.isTelevision(context);
      final history = widget.store.history;
      final all = widget.history
          ? history.map((entry) => entry.drama).toList()
          : widget.store.favorites;
      final items = all.where((drama) {
        if (!matchesDramaQuery(drama, _search.text)) return false;
        final state = widget.store.following(drama.id);
        if (widget.history) {
          if (!television || _filter.isEmpty) return true;
          final entry = widget.store.watched(drama.id);
          final continuing = entry != null && _canContinue(entry);
          return _filter == 'continue' ? continuing : !continuing;
        }
        return _filter.isEmpty ||
            (_filter == 'updates'
                ? state?.hasUpdates == true
                : state?.status.name == _filter);
      }).toList();
      if (television) return _televisionLibrary(all, items);
      final ids = items.map((drama) => drama.id).toSet();
      final resume = history
          .where(
            (entry) =>
                ids.contains(entry.drama.id) &&
                (!entry.finished ||
                    entry.drama.episodes <= 0 ||
                    entry.episode < entry.drama.episodes),
          )
          .firstOrNull;
      final header = [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.history ? '最近观看' : '我的追剧'} · ${all.length}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (widget.history && all.isNotEmpty)
                IconButton(
                  tooltip: '清空观看记录',
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              if (widget.onSearchUp != null &&
                  (event is KeyDownEvent || event is KeyRepeatEvent) &&
                  event.logicalKey == LogicalKeyboardKey.arrowUp) {
                widget.onSearchUp!();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: AdaptiveTextField(
              key: ValueKey(
                widget.history ? 'history-search' : 'favorites-search',
              ),
              controller: _search,
              focusNode: widget.searchFocusNode,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.history ? '搜索观看记录' : '搜索追剧',
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
        ),
        if (!widget.history)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                for (final filter in [
                  ('', '全部'),
                  for (final status in FollowStatus.values)
                    (status.name, status.label),
                  ('updates', '有更新'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('follow-filter-${filter.$1}'),
                      label: Text(filter.$2),
                      selected: _filter == filter.$1,
                      onSelected: (_) => setState(() => _filter = filter.$1),
                    ),
                  ),
              ],
            ),
          ),
        if (resume != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                key: const ValueKey('continue-watching'),
                leading: const Icon(Icons.play_circle_outline),
                title: Text(
                  '继续观看 · ${resume.drama.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '第 ${resume.episode} 集 · ${formatPosition(resume.position)}',
                ),
                onTap: () => widget.onContinue(resume.drama),
              ),
            ),
          ),
      ];
      final empty = StatusPanel(
        title: all.isEmpty
            ? widget.history
                  ? '还没有观看记录'
                  : '还没有追剧'
            : '没有匹配的记录',
        message: all.isEmpty ? '去发现页，挑一部喜欢的短剧。' : '可以更换搜索词或筛选条件。',
        icon: widget.history
            ? Icons.history_rounded
            : Icons.bookmark_border_rounded,
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
          return CustomScrollView(
            key: PageStorageKey(
              'saved-${widget.history}-$_filter-${_search.text}',
            ),
            slivers: [
              SliverToBoxAdapter(child: Column(children: header)),
              if (items.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: empty)
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 20),
                  sliver: SliverGrid(
                    gridDelegate: dramaGridDelegate(
                      context,
                      constraints.maxWidth - 2 * padding,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, index) => _tile(items[index]),
                      childCount: items.length,
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}
