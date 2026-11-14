import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Outline drawn by us; Material borders are all [InputBorder.none] so M3 cannot
/// paint its filled active-indicator line when the field has text.
///
/// Search icon stays on the visual left; a clear (×) appears on the visual right
/// once the field has text.
class SearchQueryField extends StatefulWidget {
  const SearchQueryField({
    super.key,
    required this.controller,
    required this.ink,
    required this.muted,
    required this.onChanged,
    this.hintText = 'Search',
    this.autofocus = true,
    this.textDirection = TextDirection.ltr,
  });

  final TextEditingController controller;
  final Color ink;
  final Color muted;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool autofocus;
  final TextDirection textDirection;

  @override
  State<SearchQueryField> createState() => _SearchQueryFieldState();
}

class _SearchQueryFieldState extends State<SearchQueryField> {
  late final FocusNode _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onControllerChanged);
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant SearchQueryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _hasText = widget.controller.text.isNotEmpty;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final next = widget.controller.text.isNotEmpty;
    if (next == _hasText) return;
    if (mounted) setState(() => _hasText = next);
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final borderColor =
        focused ? AppTheme.orange : widget.muted.withValues(alpha: 0.55);
    final isRtl = widget.textDirection == TextDirection.rtl;

    final searchIcon = Icon(Icons.search, color: widget.muted);
    final clearButton = _hasText
        ? IconButton(
            tooltip: 'Clear',
            onPressed: _clear,
            icon: Icon(Icons.close_rounded, color: widget.muted),
          )
        : null;

    final prefixIcon = isRtl ? clearButton : searchIcon;
    final suffixIcon = isRtl ? searchIcon : clearButton;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor,
          width: focused ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        textDirection: widget.textDirection,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        autocorrect: false,
        enableSuggestions: false,
        spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
        style: TextStyle(fontSize: 18, color: widget.ink),
        cursorColor: AppTheme.orange,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintTextDirection: widget.textDirection,
          hintStyle: TextStyle(color: widget.muted, fontSize: 16),
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
