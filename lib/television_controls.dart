import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'models.dart';
import 'playback_preferences.dart';
import 'video_enhancement.dart';
import 'video_enhancement_preferences.dart';
import 'video_enhancement_settings.dart';
import 'remote_widgets.dart';
import 'widgets.dart';
import 'app_layout.dart';

class TelevisionControls extends StatefulWidget {
  const TelevisionControls({
    super.key,
    required this.player,
    required this.enabled,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onPrevious,
    required this.onNext,
    required this.onMenu,
    required this.onBack,
    required this.onBoost,
  });
  final Player player;
  final bool enabled;
  final VoidCallback onTogglePlayback;
  final ValueChanged<int> onSeek;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Future<void> Function() onMenu;
  final VoidCallback onBack;
  final bool Function(bool active) onBoost;

  @override
  State<TelevisionControls> createState() => _TelevisionControlsState();
}

class _TelevisionControlsState extends State<TelevisionControls> {
  final _surface = FocusNode(debugLabel: 'tv-player-surface');
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _seekTimer;
  Timer? _holdTimer;
  Timer? _statusTimer;
  bool _statusHint = false;
  bool _menuOpen = false;
  bool _seekHint = false;
  bool _boosting = false;
  bool _upPending = false;
  double _boostRate = 2;

  @override
  void initState() {
    super.initState();
    _subscriptions.add(
      widget.player.stream.buffering.listen((_) {
        if (mounted) setState(() {});
      }),
    );
    _subscriptions.add(
      widget.player.stream.position.listen((_) {
        if (mounted && _seekHint) setState(() {});
      }),
    );
    _subscriptions.add(
      widget.player.stream.playing.distinct().listen((playing) {
        if (!mounted) return;
        if (!playing) _endBoost();
        _statusTimer?.cancel();
        setState(() => _statusHint = !_menuOpen);
        if (playing && !_menuOpen) {
          _statusTimer = Timer(const Duration(milliseconds: 900), () {
            if (mounted) setState(() => _statusHint = false);
          });
        }
      }),
    );
    _focusSurface();
  }

  @override
  void didUpdateWidget(covariant TelevisionControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _endBoost();
    if (widget.enabled && !oldWidget.enabled) _focusSurface();
  }

  void _focusSurface() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.enabled &&
          !_menuOpen &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        _surface.requestFocus();
      }
    });
  }

  Future<void> _openMenu() async {
    if (_menuOpen || !widget.enabled) return;
    _endBoost();
    _seekTimer?.cancel();
    setState(() {
      _menuOpen = true;
      _seekHint = false;
    });
    try {
      await widget.onMenu();
    } finally {
      if (mounted) {
        setState(() => _menuOpen = false);
        _focusSurface();
      }
    }
  }

  void _endBoost() {
    _holdTimer?.cancel();
    _upPending = false;
    if (!_boosting) return;
    _boosting = false;
    widget.onBoost(false);
    if (mounted) setState(() {});
  }

  void _seek(int seconds) {
    widget.onSeek(seconds);
    setState(() => _seekHint = true);
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _seekHint = false);
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.enabled || _menuOpen) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyDownEvent) {
        _upPending = true;
        _holdTimer?.cancel();
        _holdTimer = Timer(const Duration(milliseconds: 400), () {
          if (mounted &&
              _upPending &&
              widget.enabled &&
              !_menuOpen &&
              widget.onBoost(true)) {
            setState(() {
              _boostRate = widget.player.state.rate * 2;
              _boosting = true;
            });
          }
        });
      } else if (event is KeyUpEvent) {
        final open = _upPending && !_boosting;
        _endBoost();
        if (open) unawaited(_openMenu());
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      if (event is KeyDownEvent) widget.onBack();
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) unawaited(_openMenu());
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _seek(key == LogicalKeyboardKey.arrowLeft ? -10 : 10);
    } else if ([
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.gameButtonA,
      LogicalKeyboardKey.mediaPlayPause,
      LogicalKeyboardKey.space,
    ].contains(key)) {
      if (event is KeyDownEvent) widget.onTogglePlayback();
    } else if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      if (event is KeyDownEvent &&
          widget.player.state.playing != (key == LogicalKeyboardKey.mediaPlay))
        widget.onTogglePlayback();
    } else if (key == LogicalKeyboardKey.mediaTrackNext) {
      if (event is KeyDownEvent) widget.onNext?.call();
    } else if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (event is KeyDownEvent) widget.onPrevious?.call();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _seekTimer?.cancel();
    _holdTimer?.cancel();
    _statusTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _surface.dispose();
    super.dispose();
  }

  Widget _hint(String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 24),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: !widget.enabled,
    child: Focus(
      focusNode: _surface,
      onKeyEvent: _key,
      onFocusChange: (focused) {
        if (!focused) _endBoost();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _openMenu : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.enabled && widget.player.state.buffering && !_menuOpen)
              const Center(child: CircularProgressIndicator()),
            if (_seekHint && !_menuOpen)
              Center(
                child: _hint(
                  '${formatPosition(widget.player.state.position.inMilliseconds / 1000)} / ${formatPosition(widget.player.state.duration.inMilliseconds / 1000)}',
                ),
              ),
            if (widget.enabled &&
                !_menuOpen &&
                !_seekHint &&
                !widget.player.state.buffering &&
                (_statusHint || !widget.player.state.playing))
              Center(
                child: ExcludeFocus(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('tv-center-playback'),
                        tooltip: widget.player.state.playing ? '暂停' : '播放',
                        onPressed: widget.onTogglePlayback,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black87,
                          foregroundColor: Colors.white,
                          fixedSize: const Size(72, 72),
                        ),
                        icon: Icon(
                          widget.player.state.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.player.state.playing ? '正在播放' : '已暂停',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_boosting)
              Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(child: _hint('$_boostRate 倍速 · 松开恢复')),
              ),
          ],
        ),
      ),
    ),
  );
}

class TelevisionPlaybackSetting {
  const TelevisionPlaybackSetting({
    this.episode,
    this.speed,
    this.quality,
    this.autoAdvance,
    this.danmaku,
    this.preload,
    this.enhancement,
  });
  final int? episode;
  final double? speed;
  final int? quality;
  final bool? autoAdvance;
  final bool? danmaku;
  final bool? preload;
  final VideoEnhancementPreferences? enhancement;
}

class TelevisionPlayerMenu extends StatefulWidget {
  const TelevisionPlayerMenu({
    super.key,
    required this.player,
    required this.title,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onDiagnostics,
    required this.episodes,
    required this.currentIndex,
    required this.initialTab,
    required this.speed,
    required this.quality,
    required this.qualities,
    required this.favorite,
    required this.onFavorite,
    this.autoAdvance = true,
    this.danmaku = true,
    this.showDanmaku = false,
    this.danmakuStatus = '',
    this.onRetryDanmaku,
    this.preload = true,
    this.preloadStatus = '',
    this.enhancement,
    this.onCompareEnhancement,
  });
  final Player player;
  final String title;
  final VoidCallback onTogglePlayback;
  final ValueChanged<int> onSeek;
  final Future<void> Function() onDiagnostics;
  final List<Episode> episodes;
  final int currentIndex;
  final int initialTab;
  final double speed;
  final int quality;
  final List<int> qualities;
  final bool favorite;
  final VoidCallback onFavorite;
  final bool autoAdvance;
  final bool danmaku;
  final bool showDanmaku;
  final String danmakuStatus;
  final VoidCallback? onRetryDanmaku;
  final bool preload;
  final String preloadStatus;
  final VideoEnhancementController? enhancement;
  final VoidCallback? onCompareEnhancement;

  @override
  State<TelevisionPlayerMenu> createState() => _TelevisionPlayerMenuState();
}

class _TelevisionPlayerMenuState extends State<TelevisionPlayerMenu> {
  static const _labels = ['选集', '倍速', '画质', '播放设置'];
  final _tabs = List.generate(
    4,
    (i) => FocusNode(debugLabel: 'tv-menu-tab-$i'),
  );
  final _settingsFirst = FocusNode(debugLabel: 'tv-menu-auto-advance');
  final _progress = FocusNode(debugLabel: 'tv-panel-progress');
  final _play = FocusNode(debugLabel: 'tv-panel-play');
  late int _tab = widget.initialTab;
  bool _inContent = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _play.requestFocus();
    });
  }

  void _showMore() {
    setState(() => _expanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _expanded) _tabs[_tab].requestFocus();
    });
  }

  void _showBasic() {
    setState(() {
      _expanded = false;
      _inContent = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_expanded) _play.requestFocus();
    });
  }

  void _back() {
    if (_expanded) {
      _showBasic();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _play.dispose();
    _settingsFirst.dispose();
    for (final node in _tabs) {
      node.dispose();
    }
    super.dispose();
  }

  void _selectTab(int index) {
    if (_tab != index || _inContent) {
      setState(() {
        _tab = index;
        _inContent = false;
      });
    }
  }

  void _tabFocused(int index) {
    if (_inContent) {
      setState(() => _inContent = false);
      _tabs[_tab].requestFocus();
    } else {
      _selectTab(index);
    }
  }

  void _enterContent() {
    setState(() => _inContent = true);
    if (_tab == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _inContent && _tab == 3) _settingsFirst.requestFocus();
      });
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      if (event is KeyDownEvent) _back();
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) widget.onTogglePlayback();
      return KeyEventResult.handled;
    }
    if (!_tabs.any((tab) => tab.hasFocus)) return KeyEventResult.ignored;
    if (_inContent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final direction = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
      final index = (_tab + direction) % _tabs.length;
      _selectTab(index);
      _tabs[index].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _enterContent();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyDownEvent) _showBasic();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _choose(TelevisionPlaybackSetting value) =>
      Navigator.pop(context, value);

  Widget _grid({
    required List<String> keys,
    required int selected,
    required Widget Function(int, FocusNode, VoidCallback) item,
    int columns = 5,
  }) => LayoutBuilder(
    builder: (context, constraints) => RemoteGrid(
      key: ValueKey('tv-menu-grid-$_tab-$_inContent'),
      itemKeys: keys,
      columns: columns.clamp(
        1,
        (constraints.maxWidth / 110).floor().clamp(1, 8),
      ),
      itemExtent: 62,
      initialIndex: selected < 0 ? 0 : selected,
      autofocus: _inContent,
      padding: const EdgeInsets.all(8),
      itemBuilder: (_, index, node, onFocus) => item(index, node, onFocus),
    ),
  );

  Widget _content() {
    if (_tab == 0) {
      return _grid(
        keys: widget.episodes.map((e) => '${e.number}').toList(),
        selected: widget.currentIndex,
        columns: 8,
        item: (i, node, onFocus) => RemoteEpisodeButton(
          key: ValueKey('tv-select-episode-${widget.episodes[i].number}'),
          number: widget.episodes[i].number,
          vip: widget.episodes[i].vip,
          current: i == widget.currentIndex,
          focusNode: node,
          onFocus: onFocus,
          onPressed: () => _choose(TelevisionPlaybackSetting(episode: i)),
        ),
      );
    }
    if (_tab == 1) {
      return _grid(
        keys: playbackSpeeds.map((v) => 'speed-$v').toList(),
        selected: playbackSpeeds.indexOf(widget.speed),
        item: (i, node, onFocus) => RemoteTarget(
          key: ValueKey('tv-speed-${playbackSpeeds[i]}'),
          focusNode: node,
          onFocus: onFocus,
          selected: playbackSpeeds[i] == widget.speed,
          onPressed: () =>
              _choose(TelevisionPlaybackSetting(speed: playbackSpeeds[i])),
          child: Center(
            child: Text(
              '${playbackSpeeds[i]}×',
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      );
    }
    if (_tab == 2) {
      final values = [0, ...widget.qualities.where((v) => v > 0).toSet()];
      return _grid(
        keys: values.map((v) => 'quality-$v').toList(),
        selected: values.indexOf(widget.quality),
        item: (i, node, onFocus) => RemoteTarget(
          key: ValueKey('tv-quality-${values[i]}'),
          focusNode: node,
          onFocus: onFocus,
          selected: values[i] == widget.quality,
          onPressed: () =>
              _choose(TelevisionPlaybackSetting(quality: values[i])),
          child: Center(
            child: Text(
              values[i] == 0 ? '自动' : '${values[i]}P',
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              RemoteButton(
                key: const ValueKey('tv-auto-advance'),
                focusNode: _settingsFirst,
                label: widget.autoAdvance ? '自动连播：开' : '自动连播：关',
                onPressed: () => _choose(
                  TelevisionPlaybackSetting(autoAdvance: !widget.autoAdvance),
                ),
              ),
              RemoteButton(
                key: const ValueKey('tv-preload-enabled'),
                label: widget.preload ? '预加载：开' : '预加载：关',
                onPressed: () => _choose(
                  TelevisionPlaybackSetting(preload: !widget.preload),
                ),
              ),
              if (widget.showDanmaku)
                RemoteButton(
                  key: const ValueKey('tv-danmaku-enabled'),
                  label: widget.danmaku ? '弹幕：开' : '弹幕：关',
                  onPressed: () => _choose(
                    TelevisionPlaybackSetting(danmaku: !widget.danmaku),
                  ),
                ),
              RemoteButton(
                label: widget.favorite ? '取消追剧' : '加入追剧',
                onPressed: () {
                  widget.onFavorite();
                  Navigator.pop(context);
                },
              ),
              if (widget.onRetryDanmaku != null)
                RemoteButton(
                  key: const ValueKey('tv-danmaku-retry'),
                  label: '重试弹幕',
                  onPressed: widget.onRetryDanmaku,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.showDanmaku) Text(widget.danmakuStatus),
          Text(widget.preloadStatus),
          const SizedBox(height: 12),
          RemoteButton(
            key: const ValueKey('tv-diary'),
            label: '播放诊断 / 日记',
            onPressed: widget.onDiagnostics,
          ),
          if (widget.enhancement != null)
            VideoEnhancementSettings(
              controller: widget.enhancement!,
              television: true,
              onChanged: (value) =>
                  _choose(TelevisionPlaybackSetting(enhancement: value)),
              onCompare: widget.onCompareEnhancement ?? () {},
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_expanded,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _showBasic();
    },
    child: Dialog(
      alignment: Alignment.bottomCenter,
      insetPadding: EdgeInsets.zero,
      backgroundColor: const Color(0xF2181A20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        height: _expanded ? MediaQuery.sizeOf(context).height * .48 : null,
        child: Focus(
          onKeyEvent: _key,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_expanded)
                  _TelevisionTransport(
                    player: widget.player,
                    title: widget.title,
                    progressFocus: _progress,
                    playFocus: _play,
                    onTogglePlayback: widget.onTogglePlayback,
                    onSeek: widget.onSeek,
                    onPrevious: widget.currentIndex > 0
                        ? () => _choose(
                            TelevisionPlaybackSetting(
                              episode: widget.currentIndex - 1,
                            ),
                          )
                        : null,
                    onNext: widget.currentIndex + 1 < widget.episodes.length
                        ? () => _choose(
                            TelevisionPlaybackSetting(
                              episode: widget.currentIndex + 1,
                            ),
                          )
                        : null,
                    onTabs: _showMore,
                    onClose: _back,
                  ),
                if (_expanded) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < _labels.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: RemoteTarget(
                              key: ValueKey('tv-menu-tab-$i'),
                              focusNode: _tabs[i],
                              selected: _tab == i,
                              onFocus: () => _tabFocused(i),
                              onPressed: _enterContent,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Text(
                                  _labels[i],
                                  style: const TextStyle(
                                    fontSize: 22,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ExcludeFocus(
                      excluding: !_inContent,
                      child: KeyedSubtree(
                        key: ValueKey('tv-menu-content-$_tab-$_inContent'),
                        child: _content(),
                      ),
                    ),
                  ),
                ],
                if (_expanded) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '左右切换分类 · 下键进入选项 · 返回回到播控',
                    style: TextStyle(
                      fontSize: TelevisionStyle.secondary,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _TelevisionTransport extends StatefulWidget {
  const _TelevisionTransport({
    required this.player,
    required this.title,
    required this.progressFocus,
    required this.playFocus,
    required this.onSeek,
    required this.onTogglePlayback,
    required this.onPrevious,
    required this.onNext,
    required this.onTabs,
    required this.onClose,
  });
  final Player player;
  final String title;
  final FocusNode progressFocus;
  final FocusNode playFocus;
  final ValueChanged<int> onSeek;
  final VoidCallback onTogglePlayback;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onTabs;
  final VoidCallback onClose;
  @override
  State<_TelevisionTransport> createState() => _TelevisionTransportState();
}

class _TelevisionTransportState extends State<_TelevisionTransport> {
  final _subscriptions = <StreamSubscription<dynamic>>[];
  @override
  void initState() {
    super.initState();
    for (final stream in [
      widget.player.stream.position,
      widget.player.stream.duration,
      widget.player.stream.buffer,
      widget.player.stream.playing,
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (widget.progressFocus.hasFocus &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      widget.onSeek(key == LogicalKeyboardKey.arrowLeft ? -10 : 10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && !widget.progressFocus.hasFocus) {
      widget.progressFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (widget.progressFocus.hasFocus) {
        widget.playFocus.requestFocus();
      } else {
        widget.onTabs();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _action(
    String key,
    String label,
    IconData icon,
    VoidCallback? action, {
    FocusNode? focus,
  }) => RemoteTarget(
    key: ValueKey(key),
    label: label,
    focusNode: focus,
    onPressed: action,
    borderWidth: 2,
    radius: 10,
    padding: const EdgeInsets.all(4),
    child: SizedBox(
      width: TelevisionStyle.target - 12,
      height: TelevisionStyle.target - 12,
      child: Icon(
        icon,
        size: 30,
        color: action == null ? Colors.white38 : Colors.white,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = widget.player.state;
    final duration = state.duration.inMilliseconds;
    final time =
        '${formatPosition(state.position.inMilliseconds / 1000)} / ${formatPosition(duration / 1000)}';
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: TelevisionStyle.body,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                time,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: TelevisionStyle.secondary,
                ),
              ),
              const SizedBox(width: 8),
              _action(
                'tv-panel-close',
                '收起',
                Icons.close_rounded,
                widget.onClose,
              ),
            ],
          ),
          Row(
            children: [
              _action(
                'tv-previous',
                '上一集',
                Icons.skip_previous_rounded,
                widget.onPrevious,
              ),
              _action(
                'tv-play-pause',
                state.playing ? '暂停' : '播放',
                state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                widget.onTogglePlayback,
                focus: widget.playFocus,
              ),
              _action('tv-next', '下一集', Icons.skip_next_rounded, widget.onNext),
              const SizedBox(width: 10),
              Expanded(
                child: RemoteTarget(
                  key: const ValueKey('tv-progress'),
                  focusNode: widget.progressFocus,
                  label: '进度 $time，左右快进退，确认播放暂停',
                  onPressed: widget.onTogglePlayback,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Stack(
                      children: [
                        LinearProgressIndicator(
                          value: duration > 0
                              ? (state.buffer.inMilliseconds / duration).clamp(
                                  0.0,
                                  1.0,
                                )
                              : 0,
                          color: Colors.white38,
                          backgroundColor: Colors.white12,
                          minHeight: 4,
                        ),
                        LinearProgressIndicator(
                          value: duration > 0
                              ? (state.position.inMilliseconds / duration)
                                    .clamp(0.0, 1.0)
                              : 0,
                          backgroundColor: Colors.transparent,
                          minHeight: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _action(
                'tv-panel-more',
                '更多设置',
                Icons.keyboard_arrow_down_rounded,
                widget.onTabs,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
