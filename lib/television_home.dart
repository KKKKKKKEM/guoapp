import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_layout.dart';
import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'remote_widgets.dart';
import 'widgets.dart';

class TelevisionHome extends StatefulWidget {
  const TelevisionHome({
    super.key,
    required this.repository,
    required this.store,
    required this.onOpen,
    required this.onMore,
    required this.onDiscover,
    required this.onHistory,
    required this.onFollowing,
    required this.onUpdates,
    required this.onTop,
  });
  final AppRepository repository;
  final LocalStore store;
  final Future<void> Function(Drama, FocusNode) onOpen;
  final ValueChanged<Drama> onMore;
  final VoidCallback onDiscover;
  final VoidCallback onHistory;
  final VoidCallback onFollowing;
  final VoidCallback onUpdates;
  final VoidCallback onTop;
  @override
  State<TelevisionHome> createState() => _TelevisionHomeState();
}

class _TelevisionHomeState extends State<TelevisionHome> {
  final _nodes = <String, FocusNode>{};
  final _scroll = ScrollController();
  final _rows = <String, ScrollController>{};
  String? _focusedTitle;

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    for (final scroll in _rows.values) {
      scroll.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Widget _shelf(
    String id,
    String title,
    List<Drama> items,
    VoidCallback onAll, {
    bool updates = false,
    bool first = false,
  }) {
    final visible = items.take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            RemoteButton(label: '查看全部', onPressed: onAll),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          key: PageStorageKey('tv-shelf-$id'),
          controller: _rows.putIfAbsent(id, () => ScrollController()),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in visible.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 10, top: 6),
                  child: Builder(
                    builder: (context) {
                      final drama = entry.$2;
                      final key = '$id-${drama.id}';
                      final node = _nodes.putIfAbsent(
                        key,
                        () => FocusNode(debugLabel: 'tv-shelf-$key'),
                      );
                      final watched = widget.store.watched(drama.id);
                      final following = widget.store.following(drama.id);
                      return Focus(
                        canRequestFocus: false,
                        onKeyEvent: (_, event) {
                          if (event is! KeyDownEvent &&
                              event is! KeyRepeatEvent) {
                            return KeyEventResult.ignored;
                          }
                          if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowLeft &&
                                  entry.$1 == 0 ||
                              event.logicalKey ==
                                      LogicalKeyboardKey.arrowRight &&
                                  entry.$1 == visible.length - 1) {
                            return KeyEventResult.handled;
                          }
                          if (first &&
                              event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            widget.onTop();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: RemoteTarget(
                          key: ValueKey('tv-home-$key'),
                          focusNode: node,
                          focusScale: 1.03,
                          label: '${drama.title}，确认继续播放，长按确认更多操作',
                          onFocus: () =>
                              setState(() => _focusedTitle = drama.title),
                          onPressed: () => widget.onOpen(drama, node),
                          onLongPress: () => widget.onMore(drama),
                          child: SizedBox(
                            width: 228,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 128,
                                  child: DramaCover(
                                    drama: drama,
                                    repository: widget.repository,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height:
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(TelevisionStyle.body) *
                                      2.6,
                                  child: Text(
                                    drama.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: TelevisionStyle.body,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  updates
                                      ? following?.updateLabel ?? ''
                                      : watched == null
                                      ? SourceSite.byId(drama.source).name
                                      : '第 ${watched.episode} 集 · ${formatPosition(watched.position)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: TelevisionStyle.secondary,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value:
                                      watched == null || watched.duration <= 0
                                      ? 0
                                      : (watched.position / watched.duration)
                                            .clamp(0, 1),
                                  minHeight: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final continuing = widget.store.history
        .where(
          (entry) =>
              !entry.finished ||
              entry.drama.episodes <= 0 ||
              entry.episode < entry.drama.episodes,
        )
        .take(12)
        .map((entry) => entry.drama)
        .toList();
    final favorites = widget.store.favorites;
    final updates = favorites
        .where((drama) => widget.store.following(drama.id)?.hasUpdates == true)
        .take(12)
        .toList();
    final active = <String>{
      for (final drama in continuing) 'continue-${drama.id}',
      for (final drama in updates) 'updates-${drama.id}',
      for (final drama in favorites.take(12)) 'following-${drama.id}',
    };
    final removed = _nodes.keys.where((key) => !active.contains(key)).toList();
    final lostFocus = removed.any((key) => _nodes[key]!.hasFocus);
    for (final key in removed) {
      _nodes.remove(key)?.dispose();
    }
    if (lostFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
          widget.onTop();
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const PageStorageKey('tv-watch-home'),
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            children: [
              if (continuing.isNotEmpty)
                _shelf(
                  'continue',
                  '继续观看',
                  continuing,
                  widget.onHistory,
                  first: true,
                ),
              if (updates.isNotEmpty)
                _shelf(
                  'updates',
                  '追剧更新',
                  updates,
                  widget.onUpdates,
                  updates: true,
                  first: continuing.isEmpty,
                ),
              if (favorites.isNotEmpty)
                _shelf(
                  'following',
                  '我的追剧',
                  favorites,
                  widget.onFollowing,
                  first: continuing.isEmpty && updates.isEmpty,
                ),
              if (continuing.isEmpty && favorites.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '从一部喜欢的剧开始',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      const Text('观看后在这里续播，加入追剧后查看更新。'),
                      const SizedBox(height: 24),
                      RemoteButton(
                        key: const ValueKey('tv-home-discover'),
                        label: '去发现',
                        icon: Icons.explore_outlined,
                        onPressed: widget.onDiscover,
                      ),
                    ],
                  ),
                ),
              if (continuing.isNotEmpty || favorites.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: RemoteButton(
                    label: '浏览全部剧库',
                    icon: Icons.explore_outlined,
                    onPressed: widget.onDiscover,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _focusedTitle == null
                ? '确认播放 · 长按确认更多操作'
                : '$_focusedTitle · 确认播放 · 长按确认更多操作',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
