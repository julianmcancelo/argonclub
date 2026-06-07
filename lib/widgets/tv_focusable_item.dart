import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvFocusableItem extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scaleOnFocus;
  final Color focusColor;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  const TvFocusableItem({
    Key? key,
    required this.child,
    this.onPressed,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.scaleOnFocus = 1.05,
    this.focusColor = Colors.white,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.padding = EdgeInsets.zero,
  }) : super(key: key);

  @override
  State<TvFocusableItem> createState() => _TvFocusableItemState();
}

class _TvFocusableItemState extends State<TvFocusableItem> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _isFocused || _isHovered;
    
    return Padding(
      padding: widget.padding,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) {
          setState(() => _isFocused = focused);
          if (widget.onFocusChange != null) {
            widget.onFocusChange!(focused);
          }
        },
        onShowHoverHighlight: (hovered) {
          setState(() => _isHovered = hovered);
        },
        actions: {
          ActivateIntent: CallbackAction<Intent>(
            onInvoke: (intent) {
              if (widget.onPressed != null) {
                widget.onPressed!();
              }
              return null;
            },
          ),
        },
        mouseCursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: active ? widget.scaleOnFocus : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: active ? widget.focusColor : Colors.transparent,
                  width: active ? 3.0 : 0.0,
                  strokeAlign: BorderSide.strokeAlignOutside, // Previene shifts
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: widget.focusColor.withOpacity(0.5),
                          blurRadius: 12,
                          spreadRadius: 2,
                        )
                      ]
                    : [],
              ),
              child: ClipRRect(
                borderRadius: widget.borderRadius,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
