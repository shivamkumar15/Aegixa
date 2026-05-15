import 'package:flutter/material.dart';

class SailorSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final Color? inactiveColor;

  const SailorSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<SailorSwitch> createState() => _SailorSwitchState();
}

class _SailorSwitchState extends State<SailorSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
    if (widget.value) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SailorSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeColor = widget.activeColor ?? const Color(0xFFFF0066);
    final inactiveColor = widget.inactiveColor ??
        (isDark ? const Color(0xFF333333) : const Color(0xFFE5E7EB));

    return GestureDetector(
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final value = _animation.value;

          // Track dimensions
          const double width = 48.0;
          const double height = 26.0;
          const double thumbSize = 20.0;
          const double padding = 3.0;

          // Calculate thumb stretch effect
          // Front edge moves faster than back edge
          double frontProgress;
          double backProgress;

          if (_controller.status == AnimationStatus.forward || value > 0.5) {
            // Moving towards ON (Right)
            frontProgress = CurvedAnimation(
              parent: _controller,
              curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
            ).value;
            backProgress = CurvedAnimation(
              parent: _controller,
              curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
            ).value;
          } else {
            // Moving towards OFF (Left) - reverse logic
            // When reversing, 1.0 -> 0.0
            // We want the left edge to lead the move to the left.
            // But we can just use the same progress and flip the positions.
            frontProgress = CurvedAnimation(
              parent: _controller,
              curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
            ).value;
            backProgress = CurvedAnimation(
              parent: _controller,
              curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
            ).value;
          }

          final double leftPos = padding + (backProgress * (width - thumbSize - padding * 2));
          final double rightPos = padding + (frontProgress * (width - thumbSize - padding * 2)) + thumbSize;

          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              color: Color.lerp(inactiveColor, activeColor, value),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: leftPos,
                  top: padding,
                  child: Container(
                    width: (rightPos - leftPos).clamp(thumbSize, width - padding * 2),
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(thumbSize / 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
