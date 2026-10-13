import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_layout.dart';
import 'remote_widgets.dart';

class AdaptiveTextField extends StatefulWidget {
  const AdaptiveTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.autofocus = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enabled,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final bool autofocus;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool? enabled;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AdaptiveTextField> createState() => _AdaptiveTextFieldState();
}

class _AdaptiveTextFieldState extends State<AdaptiveTextField> {
  FocusNode? _ownedFocus;
  bool _editing = false;
  FocusNode get _focus =>
      widget.focusNode ??
      (_ownedFocus ??= FocusNode(
        debugLabel:
            'tv-input-${widget.decoration.labelText ?? widget.decoration.hintText ?? ''}',
      ));

  Future<void> _edit() async {
    if (_editing || widget.enabled == false) return;
    _editing = true;
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (_) =>
            _TvTextEditor(field: widget, initialValue: widget.controller.text),
      );
      if (!mounted || result == null || widget.enabled == false) return;
      widget.controller.value = TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
      widget.onChanged?.call(result);
      if (mounted) widget.onSubmitted?.call(result);
    } finally {
      _editing = false;
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true))
        _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _ownedFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppLayout.isTelevision(context)) {
      return TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        decoration: widget.decoration,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        autocorrect: widget.autocorrect,
        enableSuggestions: widget.enableSuggestions,
        enabled: widget.enabled,
        maxLength: widget.maxLength,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      );
    }
    return RemoteTarget(
      focusNode: _focus,
      autofocus: widget.autofocus,
      label:
          '${widget.decoration.labelText ?? widget.decoration.hintText ?? '输入内容'}，按确认编辑',
      onPressed: widget.enabled == false ? null : _edit,
      child: IgnorePointer(
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final text = value.text.isEmpty
                ? widget.decoration.hintText ?? '按确认输入'
                : widget.obscureText
                ? List.filled(value.text.length.clamp(0, 12), '•').join()
                : value.text;
            return InputDecorator(
              isEmpty: false,
              decoration: widget.decoration.copyWith(
                enabled: widget.enabled ?? true,
                hintText: '',
                suffixIcon: const Icon(Icons.edit_outlined),
              ),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value.text.isEmpty
                      ? Theme.of(context).hintColor
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TvTextEditor extends StatefulWidget {
  const _TvTextEditor({required this.field, required this.initialValue});
  final AdaptiveTextField field;
  final String initialValue;
  @override
  State<_TvTextEditor> createState() => _TvTextEditorState();
}

class _TvTextEditorState extends State<_TvTextEditor> {
  late final _controller = TextEditingController(text: widget.initialValue);
  bool _showText = false;
  void _submit() => Navigator.pop(context, _controller.text);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(
        LogicalKeyboardKey.escape,
        includeRepeats: false,
      ): () =>
          Navigator.pop(context),
      const SingleActivator(
        LogicalKeyboardKey.goBack,
        includeRepeats: false,
      ): () =>
          Navigator.pop(context),
      const SingleActivator(
        LogicalKeyboardKey.browserBack,
        includeRepeats: false,
      ): () =>
          Navigator.pop(context),
    },
    child: AlertDialog(
      scrollable: true,
      title: Text(
        widget.field.decoration.labelText ??
            widget.field.decoration.hintText ??
            '输入内容',
      ),
      content: SizedBox(
        width: 560,
        child: TextField(
          key: const ValueKey('tv-text-editor'),
          controller: _controller,
          autofocus: true,
          obscureText: widget.field.obscureText && !_showText,
          autocorrect: widget.field.autocorrect,
          enableSuggestions: widget.field.enableSuggestions,
          maxLength: widget.field.maxLength,
          keyboardType: widget.field.keyboardType,
          inputFormatters: widget.field.inputFormatters,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: widget.field.decoration.hintText,
            suffixIcon: widget.field.obscureText
                ? IconButton(
                    tooltip: _showText ? '隐藏内容' : '显示内容',
                    onPressed: () => setState(() => _showText = !_showText),
                    icon: Icon(
                      _showText
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  )
                : null,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: _controller.clear, child: const Text('清空')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    ),
  );
}
