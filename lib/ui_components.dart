import 'package:flutter/material.dart';

Widget buildTextField({
  required BuildContext context,
  required String label,
  required String hint,
  required TextEditingController controller,
  bool obscure = false,
  bool readOnly = false,
  TextInputType keyboardType = TextInputType.text,
  Widget? suffixIcon,
  Widget? prefixIcon,
  ValueChanged<String>? onChanged,
  String? Function(String?)? validator,
}) {
  return _AnimatedAuthTextField(
    label: label,
    hint: hint,
    controller: controller,
    obscure: obscure,
    readOnly: readOnly,
    keyboardType: keyboardType,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    onChanged: onChanged,
    validator: validator,
  );
}

class _AnimatedAuthTextField extends StatefulWidget {
  const _AnimatedAuthTextField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.obscure,
    required this.readOnly,
    required this.keyboardType,
    required this.suffixIcon,
    this.prefixIcon,
    this.onChanged,
    required this.validator,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final bool readOnly;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;

  @override
  State<_AnimatedAuthTextField> createState() => _AnimatedAuthTextFieldState();
}

class _AnimatedAuthTextFieldState extends State<_AnimatedAuthTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRaised = _isFocused || _hasText;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        TextFormField(
          focusNode: _focusNode,
          controller: widget.controller,
          obscureText: widget.obscure,
          readOnly: widget.readOnly,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
          validator: widget.validator,
          style: TextStyle(
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF111827),
          ),
          decoration: InputDecoration(
            hintText: isRaised ? widget.hint : '',
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            prefixIcon: widget.prefixIcon,
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: widget.suffixIcon,
            filled: true,
            fillColor:
                isDark ? const Color(0xFF101010) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFE2E8F0),
                )),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFE2E8F0),
                )),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: theme.colorScheme.primary, width: 1.5)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 1)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 1.5)),
          ),
        ),
        Positioned(
          left: widget.prefixIcon == null ? 12 : 76,
          top: isRaised ? 3 : 17,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isRaised
                    ? (isDark
                        ? const Color(0xFF101010)
                        : const Color(0xFFF8FAFC))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontSize: isRaised ? 11 : 14,
                  fontWeight: FontWeight.w600,
                  color: _isFocused
                      ? theme.colorScheme.primary
                      : isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF6B7280),
                ),
                child: Text(widget.label),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget buildButton({
  required BuildContext context,
  required String label,
  required bool isLoading,
  required VoidCallback? onPressed,
  bool isOutlined = false,
  Widget? icon,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  if (isOutlined) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon ?? const SizedBox.shrink(),
        label: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF111827)))
            : Text(label,
                style: TextStyle(
                    color: isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF111827),
                    fontWeight: FontWeight.w600,
                    fontSize: 16)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  return SizedBox(
    height: 52,
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : Text(label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
  );
}
Widget buildRoundedTextField({
  required BuildContext context,
  required TextEditingController controller,
  required String hint,
  bool isDark = false,
  IconData? icon,
  bool obscure = false,
  Widget? suffixIcon,
  Widget? prefixIcon,
  String? Function(String?)? validator,
  TextInputType keyboardType = TextInputType.text,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return TextFormField(
    controller: controller,
    obscureText: obscure,
    validator: validator,
    keyboardType: keyboardType,
    style: TextStyle(color: isDark ? Colors.white : Colors.black),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey[400]),
      prefixIcon: prefixIcon ?? (icon != null ? Icon(icon, color: isDark ? Colors.white54 : Colors.grey[400], size: 22) : null),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    ),
  );
}

Widget buildPrimaryButton({
  required BuildContext context,
  required String label,
  required VoidCallback? onPressed,
  required bool isLoading,
}) {
  final theme = Theme.of(context);
  return Container(
    width: double.infinity,
    height: 58,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: LinearGradient(
        colors: [
          theme.colorScheme.primary,
          theme.colorScheme.primary.withOpacity(0.8),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: theme.colorScheme.primary.withOpacity(0.3),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      child: isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
    ),
  );
}

Widget buildSocialIcon({
  required BuildContext context,
  required IconData icon,
  required VoidCallback? onPressed,
  required bool isDark,
  bool isLoading = false,
  double size = 28,
}) {
  return Container(
    width: 64,
    height: 64,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(
        color: isDark ? Colors.white10 : Colors.grey[200]!,
        width: 1,
      ),
    ),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(32),
      child: Center(
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : Icon(icon, color: isDark ? Colors.white : Colors.black87, size: size),
      ),
    ),
  );
}

class SailorLoader extends StatefulWidget {
  const SailorLoader({super.key});

  @override
  State<SailorLoader> createState() => _SailorLoaderState();
}

class _SailorLoaderState extends State<SailorLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 50,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;

          // text_713
          double letterSpacing = 1.0;
          double textX = 0.0;
          if (t < 0.4) {
            final localT = t / 0.4;
            letterSpacing = lerpDouble(1.0, 2.0, localT);
            textX = lerpDouble(0.0, 26.0, localT);
          } else if (t < 0.8) {
            final localT = (t - 0.4) / 0.4;
            letterSpacing = lerpDouble(2.0, 1.0, localT);
            textX = lerpDouble(26.0, 32.0, localT);
          } else if (t < 0.9) {
            final localT = (t - 0.8) / 0.1;
            letterSpacing = lerpDouble(1.0, 2.0, localT);
            textX = lerpDouble(32.0, 0.0, localT);
          } else {
            final localT = (t - 0.9) / 0.1;
            letterSpacing = lerpDouble(2.0, 1.0, localT);
            textX = 0.0;
          }

          // loading_713
          double barWidth = 16.0;
          double barX = 0.0;
          if (t < 0.4) {
            final localT = t / 0.4;
            barWidth = lerpDouble(16.0, 80.0, localT);
            barX = 0.0;
          } else if (t < 0.8) {
            final localT = (t - 0.4) / 0.4;
            barWidth = lerpDouble(80.0, 16.0, localT);
            barX = lerpDouble(0.0, 64.0, localT);
          } else if (t < 0.9) {
            final localT = (t - 0.8) / 0.1;
            barWidth = lerpDouble(16.0, 80.0, localT);
            barX = lerpDouble(64.0, 0.0, localT);
          } else {
            final localT = (t - 0.9) / 0.1;
            barWidth = lerpDouble(80.0, 16.0, localT);
            barX = 0.0;
          }

          // loading2_713
          double innerWidth = 16.0;
          double innerX = 0.0;
          if (t < 0.4) {
            final localT = t / 0.4;
            innerWidth = lerpDouble(16.0, 64.0, localT);
            innerX = 0.0;
          } else if (t < 0.8) {
            final localT = (t - 0.4) / 0.4;
            innerWidth = lerpDouble(64.0, 80.0, localT);
            innerX = 0.0;
          } else if (t < 0.9) {
            final localT = (t - 0.8) / 0.1;
            innerWidth = lerpDouble(80.0, 64.0, localT);
            innerX = lerpDouble(0.0, 15.0, localT);
          } else {
            final localT = (t - 0.9) / 0.1;
            innerWidth = lerpDouble(64.0, 16.0, localT);
            innerX = lerpDouble(15.0, 0.0, localT);
          }

          return Stack(
            children: [
              Positioned(
                top: 0,
                left: textX,
                child: Text(
                  'LOADING',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: letterSpacing,
                    color: const Color(0xFFE11D48),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: barX,
                child: Container(
                  width: barWidth,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: innerX,
                        child: Container(
                          width: innerWidth,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFB7185),
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
