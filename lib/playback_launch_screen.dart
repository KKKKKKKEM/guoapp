import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'app_layout.dart';
import 'remote_widgets.dart';
import 'core_bridge.dart';
import 'follow_state.dart';
import 'local_store.dart';
import 'models.dart';
import 'player_screen.dart';
import 'widgets.dart';

Future<void> openPlaybackDirectly(
  BuildContext context, {
  required Drama drama,
  required AppRepository repository,
  required LocalStore store,
}) async {
  if (AppLayout.isTelevision(context)) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaybackLaunchScreen(
          drama: drama,
          repository: repository,
          store: store,
        ),
      ),
    );
    return;
  }
  final profileEpoch = store.profileEpoch;
  try {
    final detail = await repository.detail(drama);
    if (!context.mounted || profileEpoch != store.profileEpoch) return;
    final mergedDrama = repository.catalogUpdates
        .current(drama)
        .merge(detail.drama);
    final merged = DramaDetail(
      mergedDrama,
      detail.episodes,
      warning: detail.warning,
    );
    repository.catalogUpdates.publish(mergedDrama, retryCover: true);
    await saveUserChange(context, () => store.refreshDrama(mergedDrama));
    if (!context.mounted || profileEpoch != store.profileEpoch) return;
    if (merged.episodes.isEmpty) {
      throw AppFailure('暂时没有可播放的集数');
    }
    final watched = store.watched(mergedDrama.id);
    final index = resumeEpisodeIndex(merged.episodes, watched);
    final episode = merged.episodes[index];
    if (episode.vip && mergedDrama.source != SourceSite.dsd.id) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('这是一集 VIP 内容'),
          content: const Text('站源可能只提供试看或限制播放。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('尝试播放'),
            ),
          ],
        ),
      );
      if (accepted != true || !context.mounted) return;
    }
    final position =
        watched?.episode == episode.number && watched?.finished == false
        ? watched!.position
        : 0.0;
    if (!context.mounted || profileEpoch != store.profileEpoch) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          detail: merged,
          initialIndex: index,
          initialPosition: position,
          repository: repository,
          store: store,
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted || profileEpoch != store.profileEpoch) return;
    repository.catalogUpdates.publish(
      repository.catalogUpdates.current(drama),
      retryCover: true,
    );
    final message = error is AppFailure ? error.message : '暂时无法播放，请重试';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class PlaybackLaunchScreen extends StatefulWidget {
  const PlaybackLaunchScreen({
    super.key,
    required this.drama,
    required this.repository,
    required this.store,
  });

  final Drama drama;
  final AppRepository repository;
  final LocalStore store;

  @override
  State<PlaybackLaunchScreen> createState() => _PlaybackLaunchScreenState();
}

class _PlaybackLaunchScreenState extends State<PlaybackLaunchScreen> {
  late final int _profileEpoch;
  int _generation = 0;
  String? _error;
  bool _loading = false;
  bool _confirming = false;
  DramaDetail? _ready;
  int _initialIndex = 0;
  double _initialPosition = 0;
  final _retryFocus = FocusNode(debugLabel: 'tv-launch-retry');

  @override
  void initState() {
    super.initState();
    _profileEpoch = widget.store.profileEpoch;
    unawaited(_load());
  }

  @override
  void dispose() {
    _retryFocus.dispose();
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final generation = ++_generation;
    setState(() => _error = null);
    try {
      final detail = await widget.repository.detail(widget.drama);
      if (!mounted ||
          generation != _generation ||
          _profileEpoch != widget.store.profileEpoch) {
        return;
      }
      final drama = widget.repository.catalogUpdates
          .current(widget.drama)
          .merge(detail.drama);
      final merged = DramaDetail(
        drama,
        detail.episodes,
        warning: detail.warning,
      );
      widget.repository.catalogUpdates.publish(drama, retryCover: true);
      await saveUserChange(context, () => widget.store.refreshDrama(drama));
      if (!mounted ||
          generation != _generation ||
          _profileEpoch != widget.store.profileEpoch) {
        return;
      }
      if (merged.episodes.isEmpty) {
        throw AppFailure('暂时没有可播放的集数');
      }
      final watched = widget.store.watched(drama.id);
      final index = resumeEpisodeIndex(merged.episodes, watched);
      final episode = merged.episodes[index];
      if (episode.vip && drama.source != SourceSite.dsd.id) {
        if (!mounted) return;
        setState(() => _confirming = true);
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('这是一集 VIP 内容'),
            content: const Text('站源可能只提供试看或限制播放。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('尝试播放'),
              ),
            ],
          ),
        );
        if (mounted) setState(() => _confirming = false);
        if (accepted != true) {
          if (mounted) Navigator.of(context).maybePop();
          return;
        }
        if (!mounted) {
          return;
        }
      }
      final position =
          watched?.episode == episode.number && watched?.finished == false
          ? watched!.position
          : 0.0;
      if (!mounted ||
          generation != _generation ||
          _profileEpoch != widget.store.profileEpoch) {
        return;
      }
      setState(() {
        _ready = merged;
        _initialIndex = index;
        _initialPosition = position;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error.toString());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _error != null && AppLayout.isTelevision(context))
          _retryFocus.requestFocus();
      });
      widget.repository.catalogUpdates.publish(
        widget.repository.catalogUpdates.current(widget.drama),
        retryCover: true,
      );
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready != null) {
      return PlayerScreen(
        detail: _ready!,
        initialIndex: _initialIndex,
        initialPosition: _initialPosition,
        repository: widget.repository,
        store: widget.store,
      );
    }
    final television = AppLayout.isTelevision(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _generation++;
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(
            LogicalKeyboardKey.escape,
            includeRepeats: false,
          ): () =>
              Navigator.of(context).maybePop(),
          const SingleActivator(
            LogicalKeyboardKey.goBack,
            includeRepeats: false,
          ): () =>
              Navigator.of(context).maybePop(),
        },
        child: Scaffold(
          appBar: AppBar(title: Text(widget.drama.title)),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error == null) ...[
                      if (_confirming)
                        const Icon(Icons.help_outline_rounded, size: 40)
                      else
                        const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_confirming ? '请确认是否尝试播放此集' : '正在获取剧集信息…'),
                    ] else ...[
                      const Icon(Icons.play_disabled_rounded, size: 40),
                      const SizedBox(height: 16),
                      const Text('暂时无法播放'),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      RemoteButton(
                        key: const ValueKey('tv-launch-retry'),
                        label: '重试',
                        focusNode: _retryFocus,
                        autofocus: television,
                        onPressed: _load,
                      ),
                    ],
                    const SizedBox(height: 16),
                    RemoteButton(
                      key: const ValueKey('tv-launch-cancel'),
                      label: '取消',
                      autofocus: television && _error == null,
                      onPressed: () => Navigator.of(context).maybePop(),
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
