import 'dart:async';
import 'package:flutter/material.dart';

import 'dart:math' as math;
import 'adaptive_text_field.dart';
import 'app_layout.dart';
import 'package:flutter/services.dart';

class RemoteTarget extends StatefulWidget {
  const RemoteTarget({
    super.key,
    required this.child,
    required this.onPressed,
    this.focusNode,
    this.onFocus,
    this.onLongPress,
    this.autofocus = false,
    this.selected = false,
    this.label,
    this.radius = 14,
    this.padding = const EdgeInsets.all(4),
    this.borderWidth = 3,
    this.outlined = false,
    this.focusScale = 1,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final bool selected;
  final String? label;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double borderWidth;
  final bool outlined;
  final double focusScale;

  @override
  State<RemoteTarget> createState() => _RemoteTargetState();
}

class _RemoteTargetState extends State<RemoteTarget> {
  bool _focused = false;
  Timer? _hold;
  LogicalKeyboardKey? _pressedKey;
  bool _longPressed = false;

  void _cancelHold() {
    _hold?.cancel();
    _pressedKey = null;
    _longPressed = false;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (![
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.gameButtonA,
    ].contains(event.logicalKey)) {
      if (event is KeyDownEvent) _cancelHold();
      return KeyEventResult.ignored;
    }
    if (widget.onLongPress == null) {
      return event is KeyRepeatEvent
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is KeyDownEvent && _pressedKey == null) {
      _pressedKey = event.logicalKey;
      _longPressed = false;
      _hold = Timer(const Duration(milliseconds: 650), () {
        if (!mounted ||
            !_focused ||
            _pressedKey == null ||
            widget.onPressed == null) {
          return;
        }
        _longPressed = true;
        widget.onLongPress?.call();
      });
    } else if (event is KeyUpEvent && _pressedKey == event.logicalKey) {
      final activate = !_longPressed;
      _cancelHold();
      if (activate) widget.onPressed?.call();
    }
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(covariant RemoteTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) _cancelHold();
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _key,
    child: FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.onPressed != null,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      onFocusChange: (focused) {
        if (!focused) _cancelHold();
        if (mounted) setState(() => _focused = focused);
        if (focused) {
          widget.onFocus?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _focused) {
              Scrollable.ensureVisible(
                context,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              );
            }
          });
        }
      },
      child: Semantics(
        button: true,
        enabled: widget.onPressed != null,
        selected: widget.selected,
        focused: _focused,
        label: widget.label,
        onLongPress: widget.onLongPress,
        child: MouseRegion(
          cursor: widget.onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            onLongPress: widget.onLongPress,
            child: AnimatedScale(
              scale: _focused ? widget.focusScale : 1,
              duration: const Duration(milliseconds: 140),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: _focused
                      ? Theme.of(context).colorScheme.primaryContainer
                      : widget.selected
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(widget.radius),
                  border: Border.all(
                    color: _focused
                        ? Theme.of(context).colorScheme.primary
                        : widget.outlined
                        ? Theme.of(context).colorScheme.outlineVariant
                        : Colors.transparent,
                    width: widget.borderWidth,
                  ),
                ),
                child: ExcludeFocus(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class RemoteButton extends StatelessWidget {
  const RemoteButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.onFocus,
    this.maxLines = 1,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;
  final int maxLines;

  @override
  Widget build(BuildContext context) => RemoteTarget(
    onPressed: onPressed,
    selected: selected,
    autofocus: autofocus,
    focusNode: focusNode,
    onFocus: onFocus,
    label: label,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 22), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TelevisionStyle.body,
                color: onPressed == null
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class RemoteGrid extends StatefulWidget {
  const RemoteGrid({
    super.key,
    required this.itemKeys,
    required this.columns,
    required this.itemExtent,
    required this.itemBuilder,
    this.controller,
    this.spacing = 14,
    this.padding = const EdgeInsets.all(18),
    this.footer,
    this.initialIndex = 0,
    this.autofocus = false,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });
  final List<String> itemKeys;
  final int columns;
  final double itemExtent;
  final double spacing;
  final EdgeInsets padding;
  final ScrollController? controller;
  final Widget? footer;
  final int initialIndex;
  final bool autofocus;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final Widget Function(BuildContext, int, FocusNode, VoidCallback) itemBuilder;

  @override
  State<RemoteGrid> createState() => _RemoteGridState();
}

class _RemoteGridState extends State<RemoteGrid> {
  final _ownScroll = ScrollController();
  final _footerFocus = FocusScopeNode(debugLabel: 'remote-grid-footer');
  final _nodes = <String, FocusNode>{};
  String? _focused;
  String? _target;
  int _generation = 0;
  bool _restored = false;
  ScrollController get _scroll => widget.controller ?? _ownScroll;

  FocusNode _node(int index) => _nodes.putIfAbsent(
    widget.itemKeys[index],
    () => FocusNode(debugLabel: 'remote-${widget.itemKeys[index]}'),
  );

  Future<void> _focusFooter() async {
    final generation = ++_generation;
    _target = null;
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted || generation != _generation || _footerFocus.context == null) {
      return;
    }
    if (!_footerFocus.traversalDescendants.any(
      (node) => node.canRequestFocus && !node.skipTraversal,
    )) {
      return;
    }
    _footerFocus.requestFocus();
    _footerFocus.nextFocus();
  }

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.itemKeys.isNotEmpty) {
          _focusAt(widget.initialIndex.clamp(0, widget.itemKeys.length - 1));
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored || widget.key == null || !AppLayout.isTelevision(context)) {
      return;
    }
    _restored = true;
    if (widget.autofocus) return;
    final saved = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: widget.key);
    final index = saved is String ? widget.itemKeys.indexOf(saved) : -1;
    if (index >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !(ModalRoute.of(context)?.isCurrent ?? true) ||
            index >= widget.itemKeys.length) {
          return;
        }
        if (FocusManager.instance.primaryFocus is FocusScopeNode) {
          _focusAt(index);
        }
      });
    }
  }

  void _focusAt(int index) {
    final generation = ++_generation;
    _target = widget.itemKeys[index];
    final node = _node(index);

    if (_scroll.hasClients) {
      final row = index ~/ widget.columns;
      final itemTop =
          widget.padding.top + row * (widget.itemExtent + widget.spacing);
      final itemBottom = itemTop + widget.itemExtent;
      final currentOffset = _scroll.offset;
      final viewportHeight = _scroll.position.viewportDimension;

      double? targetOffset;
      if (row == 0) {
        if (currentOffset > 0.0) {
          targetOffset = 0.0;
        }
      } else if (itemTop < currentOffset + widget.padding.top) {
        targetOffset = itemTop - widget.padding.top;
      } else if (itemBottom >
          currentOffset + viewportHeight - widget.padding.bottom) {
        targetOffset = itemBottom - viewportHeight + widget.padding.bottom;
      }

      if (targetOffset != null) {
        final clamped = targetOffset.clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        );
        if ((clamped - currentOffset).abs() > 1.0) {
          _scroll.animateTo(
            clamped,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }

    if (node.context != null) {
      node.requestFocus();
      _target = null;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && node.context != null) {
          node.requestFocus();
          _target = null;
        }
      });
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_footerFocus.hasFocus &&
        event.logicalKey == LogicalKeyboardKey.arrowUp &&
        widget.itemKeys.isNotEmpty) {
      final previous = widget.itemKeys.indexOf(_focused ?? '');
      _focusAt(previous >= 0 ? previous : widget.itemKeys.length - 1);
      return KeyEventResult.handled;
    }
    if (_focused == null || !(_nodes[_focused]?.hasFocus ?? false)) {
      return KeyEventResult.ignored;
    }
    final index = widget.itemKeys.indexOf(_target ?? _focused!);
    if (index < 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final int next;
    if (key == LogicalKeyboardKey.arrowDown) {
      final lastRow = (widget.itemKeys.length - 1) ~/ widget.columns;
      if (index ~/ widget.columns == lastRow) {
        if (widget.footer != null) {
          unawaited(_focusFooter());
          return KeyEventResult.handled;
        }
        if (_scroll.hasClients &&
            _scroll.offset < _scroll.position.maxScrollExtent - 1.0) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
          );
          return KeyEventResult.handled;
        }
        if (widget.onDown != null) {
          widget.onDown!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      next = (index + widget.columns).clamp(0, widget.itemKeys.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (index < widget.columns) {
        if (widget.onUp != null) {
          widget.onUp!();
          return KeyEventResult.handled;
        }
        if (_scroll.hasClients && _scroll.offset > 1.0) {
          _scroll.animateTo(
            0.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
          );
          return KeyEventResult.handled;
        }
        FocusScope.of(context).focusInDirection(TraversalDirection.up);
        return KeyEventResult.handled;
      }
      next = index - widget.columns;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (index % widget.columns == widget.columns - 1 ||
          index == widget.itemKeys.length - 1) {
        widget.onRight?.call();
        return KeyEventResult.handled;
      }
      next = index + 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (index % widget.columns == 0) {
        widget.onLeft?.call();
        return KeyEventResult.handled;
      }
      next = index - 1;
    } else {
      return KeyEventResult.ignored;
    }
    if (next < 0 || next >= widget.itemKeys.length) {
      return KeyEventResult.ignored;
    }
    _focusAt(next);
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(covariant RemoteGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final removed = _nodes.keys
        .where((key) => !widget.itemKeys.contains(key))
        .toList();
    final restore = removed.any((key) => _nodes[key]!.hasFocus);
    final index = oldWidget.itemKeys.indexOf(_focused ?? '');
    for (final key in removed) {
      _nodes.remove(key)?.dispose();
    }
    if (_focused != null && !widget.itemKeys.contains(_focused)) {
      _focused = null;
      _target = null;
      _generation++;
    }
    if (restore && widget.itemKeys.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.itemKeys.isNotEmpty) {
          _focusAt(index.clamp(0, widget.itemKeys.length - 1));
        }
      });
    }
  }

  @override
  void dispose() {
    _footerFocus.dispose();
    _generation++;
    for (final node in _nodes.values) {
      node.dispose();
    }
    _ownScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _key,
    child: CustomScrollView(
      controller: _scroll,
      key: widget.key == null ? null : PageStorageKey(widget.key),
      slivers: [
        SliverPadding(
          padding: widget.padding,
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.columns,
              mainAxisExtent: widget.itemExtent,
              crossAxisSpacing: widget.spacing,
              mainAxisSpacing: widget.spacing,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final key = widget.itemKeys[index];
              final node = _node(index);
              if (_target == key) {
                final generation = _generation;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted &&
                      generation == _generation &&
                      _target == key &&
                      node.context != null &&
                      (ModalRoute.of(context)?.isCurrent ?? true)) {
                    node.requestFocus();
                    _target = null;
                  }
                });
              }
              return widget.itemBuilder(context, index, node, () {
                _focused = key;
                if (widget.key != null) {
                  PageStorage.maybeOf(
                    context,
                  )?.writeState(context, key, identifier: widget.key);
                }
              });
            }, childCount: widget.itemKeys.length),
          ),
        ),
        if (widget.footer != null)
          SliverToBoxAdapter(
            child: FocusScope(node: _footerFocus, child: widget.footer!),
          ),
      ],
    ),
  );
}

class RemoteEpisodeButton extends StatelessWidget {
  const RemoteEpisodeButton({
    super.key,
    required this.number,
    required this.onPressed,
    this.vip = false,
    this.current = false,
    this.compact = false,
    this.focusNode,
    this.onFocus,
  });
  final int number;
  final bool vip;
  final bool current;
  final bool compact;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) => RemoteTarget(
    focusNode: focusNode,
    onFocus: onFocus,
    selected: current,
    radius: compact ? 8 : 14,
    padding: compact ? const EdgeInsets.all(2) : const EdgeInsets.all(4),
    borderWidth: compact ? 1.2 : 2,
    outlined: true,
    onPressed: onPressed,
    label: '第 $number 集${current ? '，当前选中' : ''}${vip ? '，VIP 试看' : ''}',
    child: Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (current && !compact) const Icon(Icons.check_rounded, size: 18),
          Flexible(
            child: Text(
              '$number',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact && !AppLayout.isTelevision(context)
                    ? 14
                    : TelevisionStyle.body,
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (vip) ...[
            SizedBox(width: compact ? 2 : 4),
            Icon(
              Icons.workspace_premium_rounded,
              color: Theme.of(context).colorScheme.tertiary,
              size: compact ? 15 : 18,
            ),
          ],
        ],
      ),
    ),
  );
}

class TelevisionSearchDialog extends StatefulWidget {
  const TelevisionSearchDialog({
    super.key,
    required this.initialValue,
    required this.title,
    this.suggestions,
    this.recentSearches = const [],
    this.onCancel,
  });
  final Future<List<String>> Function(String)? suggestions;
  final List<String> recentSearches;
  final VoidCallback? onCancel;
  final String initialValue;
  final String title;

  @override
  State<TelevisionSearchDialog> createState() => _TelevisionSearchDialogState();
}

class _TelevisionSearchDialogState extends State<TelevisionSearchDialog> {
  late final _input = TextEditingController(text: widget.initialValue);
  final _keyboard = FocusScopeNode(debugLabel: 'tv-search-keyboard');
  final _matches = FocusScopeNode(debugLabel: 'tv-search-matches');
  List<String> _results = [];
  bool _searching = false;
  String? _focusedSuggestion;
  Timer? _debounce;
  int _generation = 0;
  String get _query => _input.text;

  static const _keys = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
  ];

  @override
  void initState() {
    super.initState();
    if (_query.trim().isNotEmpty) {
      _searching = widget.suggestions != null;
      _fetchSuggestions(_query.trim(), ++_generation);
    }
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    widget.onCancel?.call();
    _input.dispose();
    _keyboard.dispose();
    _matches.dispose();
    super.dispose();
  }

  void _changeQuery(String text) {
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _onQueryChanged();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _query.trim();
    setState(() {
      _focusedSuggestion = null;
      _results = [];
      _searching = query.isNotEmpty && widget.suggestions != null;
    });
    if (!_searching) return;
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _fetchSuggestions(query, generation),
    );
  }

  Future<void> _fetchSuggestions(String query, int generation) async {
    if (widget.suggestions == null) return;
    try {
      final list = await widget.suggestions!(query);
      if (!mounted || generation != _generation || query != _query.trim()) {
        return;
      }
      setState(() {
        _results = list
            .where((item) => item.trim().isNotEmpty)
            .toSet()
            .take(10)
            .toList();
        _searching = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  void _submit(String text) {
    final query = text.trim();
    if (query.isNotEmpty) Navigator.pop(context, query);
  }

  void _focusScope(FocusScopeNode scope) {
    scope.requestFocus();
    scope.nextFocus();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final items = _query.isEmpty ? widget.recentSearches : _results;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: SizedBox(
        width: math.min(960, size.width - 64),
        height: math.min(600, size.height - 80),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: SizedBox(
              height: math.max(420, constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭搜索',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    AdaptiveTextField(
                      key: const ValueKey('tv-search-input'),
                      controller: _input,
                      autofocus: true,
                      maxLength: 80,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: '输入剧名',
                        hintText: '按确认打开输入法，可输入中文',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (_) => _onQueryChanged(),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: FocusScope(
                              node: _keyboard,
                              child: RemoteGrid(
                                itemKeys: _keys,
                                columns: 6,
                                itemExtent: 48,
                                spacing: 6,
                                padding: const EdgeInsets.all(4),
                                onRight: items.isEmpty
                                    ? null
                                    : () => _focusScope(_matches),
                                footer: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: RemoteButton(
                                          label: '退格',
                                          onPressed: _query.isEmpty
                                              ? null
                                              : () => _changeQuery(
                                                  String.fromCharCodes(
                                                    _query.runes.toList()
                                                      ..removeLast(),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      Expanded(
                                        child: RemoteButton(
                                          label: '清空',
                                          onPressed: _query.isEmpty
                                              ? null
                                              : () => _changeQuery(''),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                itemBuilder: (_, index, node, onFocus) =>
                                    RemoteTarget(
                                      key: ValueKey('tv-key-${_keys[index]}'),
                                      focusNode: node,
                                      onFocus: onFocus,
                                      onPressed: () => _changeQuery(
                                        '$_query${_keys[index]}',
                                      ),
                                      child: Center(
                                        child: Text(
                                          _keys[index],
                                          style: const TextStyle(fontSize: 22),
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          const VerticalDivider(width: 1),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _query.isEmpty
                                      ? '历史搜索'
                                      : _searching
                                      ? '正在匹配…'
                                      : '联想结果',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: items.isEmpty
                                      ? Center(
                                          child: Text(
                                            _searching
                                                ? '搜索中…'
                                                : _query.isEmpty
                                                ? '确认输入中文，或使用左侧字母数字键盘。'
                                                : '按搜索查找当前输入；选择联想可搜索完整剧名。',
                                            textAlign: TextAlign.center,
                                          ),
                                        )
                                      : FocusScope(
                                          node: _matches,
                                          child: RemoteGrid(
                                            key: ValueKey(
                                              'search-matches-${_query.isEmpty}',
                                            ),
                                            itemKeys: items,
                                            columns: 1,
                                            itemExtent: 88,
                                            spacing: 8,
                                            padding: const EdgeInsets.all(4),
                                            onLeft: () =>
                                                _focusScope(_keyboard),
                                            itemBuilder:
                                                (
                                                  _,
                                                  index,
                                                  node,
                                                  onFocus,
                                                ) => RemoteButton(
                                                  key: ValueKey(
                                                    _query.isEmpty
                                                        ? 'recent-${items[index]}'
                                                        : 'suggest-$index',
                                                  ),
                                                  focusNode: node,
                                                  onFocus: () {
                                                    onFocus();
                                                    setState(
                                                      () => _focusedSuggestion =
                                                          items[index],
                                                    );
                                                  },
                                                  label: items[index],
                                                  maxLines: 2,
                                                  onPressed: () =>
                                                      _submit(items[index]),
                                                ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _focusedSuggestion ?? '字母数字快捷输入 · 中文按确认编辑',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        RemoteButton(
                          key: const ValueKey('tv-search-submit'),
                          label: '搜索',
                          icon: Icons.search_rounded,
                          onPressed: _query.trim().isEmpty
                              ? null
                              : () => _submit(_query),
                        ),
                      ],
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
