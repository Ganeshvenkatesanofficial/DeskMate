import 'package:flutter/material.dart';

/// A polished, circular close button inspired by macOS window controls and
/// modern dialog dismissing chips. Uses exact coral-red (#FF5C60) with
/// deep maroon (#802F30) cross icon, featuring smooth hover interactions.
class CircularCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

  const CircularCloseButton({
    super.key,
    required this.onTap,
    this.tooltip,
    this.size = 16.0,
  });

  @override
  State<CircularCloseButton> createState() => _CircularCloseButtonState();
}

class _CircularCloseButtonState extends State<CircularCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isHovered
                ? const Color(0xFFFF454A)
                : const Color(0xFFFF5C60),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF5C60).withValues(alpha: 0.45),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(
              Icons.close_rounded,
              size: widget.size * 0.625,
              color: _isHovered
                  ? const Color(0xFF4A1012)
                  : const Color(0xFF802F30),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
