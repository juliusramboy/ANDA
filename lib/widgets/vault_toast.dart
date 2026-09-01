import 'dart:async';
import 'package:flutter/material.dart';

enum ToastType { success, error, info, warning }

class VaultToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void showSuccess(BuildContext context, String message, {String? title}) {
    show(context, message: message, title: title ?? 'Success', type: ToastType.success);
  }

  static void showError(BuildContext context, String message, {String? title}) {
    show(context, message: message, title: title ?? 'Error', type: ToastType.error);
  }

  static void showInfo(BuildContext context, String message, {String? title}) {
    show(context, message: message, title: title ?? 'Notification', type: ToastType.info);
  }

  static void showWarning(BuildContext context, String message, {String? title}) {
    show(context, message: message, title: title ?? 'Warning', type: ToastType.warning);
  }

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    ToastType type = ToastType.info,
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AnimatedToastWidget(
        title: title,
        message: message,
        type: type,
        duration: duration,
        onDismiss: () {
          _dismissTimer?.cancel();
          if (_currentEntry == entry) {
            _currentEntry?.remove();
            _currentEntry = null;
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration + const Duration(milliseconds: 400), () {
      if (_currentEntry == entry) {
        _currentEntry?.remove();
        _currentEntry = null;
      }
    });
  }
}

class _AnimatedToastWidget extends StatefulWidget {
  final String? title;
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDismiss;

  const _AnimatedToastWidget({
    this.title,
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_AnimatedToastWidget> createState() => _AnimatedToastWidgetState();
}

class _AnimatedToastWidgetState extends State<_AnimatedToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 280),
    );

    _slideAnimation = Tween<double>(begin: -60.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );

    _animController.forward();

    Future.delayed(widget.duration, () {
      if (mounted) {
        _animController.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _dismissNow() {
    _animController.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    Color accentColor;
    Color iconBgColor;
    IconData icon;

    switch (widget.type) {
      case ToastType.success:
        accentColor = const Color(0xFF10B981); // Emerald
        iconBgColor = const Color(0xFF10B981).withValues(alpha: 0.15);
        icon = Icons.check_circle_rounded;
        break;
      case ToastType.error:
        accentColor = const Color(0xFFEF4444); // Crimson
        iconBgColor = const Color(0xFFEF4444).withValues(alpha: 0.15);
        icon = Icons.error_outline_rounded;
        break;
      case ToastType.warning:
        accentColor = const Color(0xFFF59E0B); // Amber
        iconBgColor = const Color(0xFFF59E0B).withValues(alpha: 0.15);
        icon = Icons.warning_amber_rounded;
        break;
      case ToastType.info:
        accentColor = const Color(0xFF6366F1); // Indigo / Violet
        iconBgColor = const Color(0xFF6366F1).withValues(alpha: 0.15);
        icon = Icons.notifications_active_outlined;
        break;
    }

    return Positioned(
      top: topPadding > 0 ? topPadding + 10 : 20,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _slideAnimation.value),
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _fadeAnimation.value.clamp(0.0, 1.0),
                  child: child,
                ),
              ),
            );
          },
          child: Dismissible(
            key: UniqueKey(),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onDismiss(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A), // Deep sleek navy slate
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Animated Icon Badge
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Message Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.title != null) ...[
                          Text(
                            widget.title!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          widget.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Close button
                  GestureDetector(
                    onTap: _dismissNow,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
