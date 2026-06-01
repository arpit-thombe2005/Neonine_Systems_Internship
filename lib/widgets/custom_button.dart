import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 0.05,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _controller.forward();
  void _onTapUp(TapUpDetails _) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = widget.onPressed == null || widget.isLoading;

    return GestureDetector(
      onTapDown: isDisabled ? null : _onTapDown,
      onTapUp: isDisabled ? null : _onTapUp,
      onTapCancel: isDisabled ? null : _onTapCancel,
      onTap: isDisabled ? null : widget.onPressed,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 58,
          decoration: BoxDecoration(
            color: widget.isOutlined
                ? Colors.transparent
                : (isDisabled ? const Color(0xFF2A2A2A) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: widget.isOutlined
                ? Border.all(
                    color: isDisabled
                        ? const Color(0xFF3A3A3A)
                        : Colors.white.withOpacity(0.4),
                    width: 1.5,
                  )
                : null,
            boxShadow: widget.isOutlined || isDisabled
                ? null
                : [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.08),
                      blurRadius: 20,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Center(
            child: widget.isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.isOutlined ? Colors.white70 : Colors.black,
                      ),
                    ),
                  )
                : Text(
                    widget.label,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: widget.isOutlined
                          ? (isDisabled ? Colors.white30 : Colors.white70)
                          : (isDisabled ? Colors.white30 : Colors.black),
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
