import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─── NAV BAR ─────────────────────────────────────────────────────────────────

class VaultFloatingNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const VaultFloatingNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Sliding background indicator
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.fastOutSlowIn,
            alignment: currentIndex == 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF374151),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          // Interactive Text buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(0),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: currentIndex == 0 ? Colors.white : const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                      child: const Text('DASHBOARD'),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(1),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: currentIndex == 1 ? Colors.white : const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                      child: const Text('LEDGER'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── NAVY HERO CARD ──────────────────────────────────────────────────────────

class NavyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const NavyCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

// ─── STAT CARD ───────────────────────────────────────────────────────────────

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sublabel;

  const StatCard(
      {super.key,
      required this.label,
      required this.value,
      required this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark)),
          Text(sublabel,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textGrey)),
        ],
      ),
    );
  }
}

// ─── STATUS DOT ──────────────────────────────────────────────────────────────

class StatusDot extends StatelessWidget {
  final String status;

  const StatusDot({super.key, required this.status});

  Color get color {
    switch (status) {
      case 'active':
        return AppTheme.green;
      case 'overdue':
        return AppTheme.red;
      case 'fully_paid':
        return AppTheme.blue;
      default:
        return AppTheme.yellow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─── STATUS BADGE ────────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }
}

// ─── YELLOW BUTTON ───────────────────────────────────────────────────────────

class YellowButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  const YellowButton(
      {super.key, required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.yellow,
          foregroundColor: AppTheme.navy,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          elevation: 0,
        ),
      ),
    );
  }
}

// ─── OUTLINE BUTTON ──────────────────────────────────────────────────────────

class OutlineButton2 extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  const OutlineButton2(
      {super.key, required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.navy,
          side: const BorderSide(color: AppTheme.navy),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ),
      ),
    );
  }
}

// ─── SECTION HEADER ──────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader(
      {super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textGrey,
                letterSpacing: 0.5)),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(actionLabel!,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navy)),
          ),
      ],
    );
  }
}

// ─── INPUT FIELD ─────────────────────────────────────────────────────────────

class VaultTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final Widget? prefix;
  final Widget? suffix;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final int maxLines;

  const VaultTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.keyboardType,
    this.prefix,
    this.suffix,
    this.readOnly = false,
    this.onTap,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textGrey,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          onTap: onTap,
          validator: validator,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppTheme.textGrey, fontSize: 14),
            prefixIcon: prefix,
            suffixIcon: suffix,
            filled: true,
            fillColor: AppTheme.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.lightGrey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppTheme.navy, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.red),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── ANIMATED AVATAR ─────────────────────────────────────────────────────────

class AnimatedAvatar extends StatefulWidget {
  final String name;
  final double size;

  const AnimatedAvatar({
    super.key,
    required this.name,
    this.size = 40.0,
  });

  @override
  State<AnimatedAvatar> createState() => _AnimatedAvatarState();
}

class _AnimatedAvatarState extends State<AnimatedAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _AvatarPainter(
            name: widget.name,
            animationValue: _controller.value,
          ),
        );
      },
    );
  }
}

class _AvatarPainter extends CustomPainter {
  final String name;
  final double animationValue;

  _AvatarPainter({required this.name, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final seed = _getSeed(name);

    final List<List<Color>> palettes = [
      [const Color(0xFF6366F1), const Color(0xFF4338CA)], // Indigo
      [const Color(0xFFF97316), const Color(0xFFC2410C)], // Orange
      [const Color(0xFF14B8A6), const Color(0xFF0F766E)], // Teal
      [const Color(0xFFEC4899), const Color(0xFFBE185D)], // Rose
      [const Color(0xFF8B5CF6), const Color(0xFF6D28D9)], // Violet
      [const Color(0xFF06B6D4), const Color(0xFF0891B2)], // Cyan
    ];

    final List<Color> skinTones = [
      const Color(0xFFFFE0BD),
      const Color(0xFFFFD1A9),
      const Color(0xFFF1C27D),
      const Color(0xFFE0AC69),
      const Color(0xFFC68642),
      const Color(0xFF8D5524),
    ];

    final List<Color> hairColors = [
      const Color(0xFF1A1A1A),
      const Color(0xFFF59E0B),
      const Color(0xFFEA580C),
      const Color(0xFF64748B),
      const Color(0xFFEC4899),
      const Color(0xFF10B981),
    ];

    final palette = palettes[seed % palettes.length];
    final skinTone = skinTones[(seed >> 2) % skinTones.length];
    final hairColor = hairColors[(seed >> 4) % hairColors.length];
    final hairStyle = (seed >> 6) % 5; // 0: bald/eyebrows, 1: short, 2: curly, 3: cap, 4: long
    final hasGlasses = ((seed >> 8) % 3) == 0;
    final mouthStyle = (seed >> 10) % 3; // 0: smile, 1: open smile, 2: smirk

    // 1. Draw Background circle with gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: palette,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawCircle(Offset(w / 2, h / 2), w / 2, bgPaint);

    // Calculate animation values
    // Bobbing: vertical shift of the face
    final double bob = sin(animationValue * 2 * pi) * (h * 0.03);

    // Blinking: quick blink between 0.85 and 0.95
    double blinkScale = 1.0;
    if (animationValue >= 0.85 && animationValue < 0.90) {
      blinkScale = (0.90 - animationValue) / 0.05;
    } else if (animationValue >= 0.90 && animationValue < 0.95) {
      blinkScale = (animationValue - 0.90) / 0.05;
    }

    final double faceCenterX = w / 2;
    final double faceCenterY = h * 0.52 + bob;
    final double faceRadius = w * 0.32;

    // 2. Draw neck
    final neckPaint = Paint()..color = skinTone.withValues(alpha: 0.9);
    final neckRect = Rect.fromCenter(
      center: Offset(faceCenterX, faceCenterY + faceRadius * 0.9),
      width: faceRadius * 0.5,
      height: faceRadius * 0.6,
    );
    canvas.drawRect(neckRect, neckPaint);

    // 3. Draw Face Circle
    final facePaint = Paint()..color = skinTone;
    canvas.drawCircle(Offset(faceCenterX, faceCenterY), faceRadius, facePaint);

    // 4. Draw Hair Back (for long hair style)
    if (hairStyle == 4) {
      final backHairPaint = Paint()..color = hairColor;
      canvas.drawRect(
        Rect.fromLTRB(faceCenterX - faceRadius, faceCenterY, faceCenterX + faceRadius, faceCenterY + faceRadius * 1.1),
        backHairPaint,
      );
    }

    // 5. Draw Eyes
    final eyeY = faceCenterY - faceRadius * 0.15;
    final eyeOffsetX = faceRadius * 0.35;
    final eyeWidth = faceRadius * 0.15;
    final eyeHeight = faceRadius * 0.15;

    final eyePaint = Paint()..color = const Color(0xFF1E293B);

    // Left Eye
    if (blinkScale < 0.15) {
      final eyePath = Path()
        ..moveTo(faceCenterX - eyeOffsetX - eyeWidth / 2, eyeY)
        ..quadraticBezierTo(faceCenterX - eyeOffsetX, eyeY + eyeHeight * 0.1, faceCenterX - eyeOffsetX + eyeWidth / 2, eyeY);
      final linePaint = Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(eyePath, linePaint);
    } else {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(faceCenterX - eyeOffsetX, eyeY),
          width: eyeWidth,
          height: eyeHeight * blinkScale,
        ),
        eyePaint,
      );
    }

    // Right Eye
    if (blinkScale < 0.15) {
      final eyePath = Path()
        ..moveTo(faceCenterX + eyeOffsetX - eyeWidth / 2, eyeY)
        ..quadraticBezierTo(faceCenterX + eyeOffsetX, eyeY + eyeHeight * 0.1, faceCenterX + eyeOffsetX + eyeWidth / 2, eyeY);
      final linePaint = Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(eyePath, linePaint);
    } else {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(faceCenterX + eyeOffsetX, eyeY),
          width: eyeWidth,
          height: eyeHeight * blinkScale,
        ),
        eyePaint,
      );
    }

    // 6. Draw Glasses if applicable
    if (hasGlasses) {
      final glassPaint = Paint()
        ..color = const Color(0xFF1E1E2C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.025;
      canvas.drawCircle(Offset(faceCenterX - eyeOffsetX, eyeY), eyeWidth * 1.0, glassPaint);
      canvas.drawCircle(Offset(faceCenterX + eyeOffsetX, eyeY), eyeWidth * 1.0, glassPaint);
      canvas.drawLine(
        Offset(faceCenterX - eyeOffsetX + eyeWidth * 0.7, eyeY),
        Offset(faceCenterX + eyeOffsetX - eyeWidth * 0.7, eyeY),
        glassPaint,
      );
    }

    // 7. Draw Cheeks (Blush)
    final blushPaint = Paint()..color = const Color(0xFFFF8B8B).withValues(alpha: 0.3);
    canvas.drawCircle(Offset(faceCenterX - faceRadius * 0.55, faceCenterY + faceRadius * 0.15), faceRadius * 0.1, blushPaint);
    canvas.drawCircle(Offset(faceCenterX + faceRadius * 0.55, faceCenterY + faceRadius * 0.15), faceRadius * 0.1, blushPaint);

    // 8. Draw Mouth
    final mouthY = faceCenterY + faceRadius * 0.3;
    final mouthPaint = Paint()
      ..color = const Color(0xFF882424)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    final mouthWidth = faceRadius * 0.35;
    final mouthPath = Path();

    if (mouthStyle == 0) {
      mouthPath.moveTo(faceCenterX - mouthWidth / 2, mouthY - faceRadius * 0.05);
      mouthPath.quadraticBezierTo(faceCenterX, mouthY + faceRadius * 0.15, faceCenterX + mouthWidth / 2, mouthY - faceRadius * 0.05);
      canvas.drawPath(mouthPath, mouthPaint);
    } else if (mouthStyle == 1) {
      final openMouthPaint = Paint()
        ..color = const Color(0xFF882424)
        ..style = PaintingStyle.fill;
      mouthPath.moveTo(faceCenterX - mouthWidth / 2, mouthY);
      mouthPath.quadraticBezierTo(faceCenterX, mouthY + faceRadius * 0.2, faceCenterX + mouthWidth / 2, mouthY);
      mouthPath.quadraticBezierTo(faceCenterX, mouthY, faceCenterX - mouthWidth / 2, mouthY);
      canvas.drawPath(mouthPath, openMouthPaint);
    } else {
      mouthPath.moveTo(faceCenterX - mouthWidth / 2, mouthY);
      mouthPath.quadraticBezierTo(faceCenterX - mouthWidth * 0.1, mouthY + faceRadius * 0.06, faceCenterX + mouthWidth * 0.5, mouthY - faceRadius * 0.06);
      canvas.drawPath(mouthPath, mouthPaint);
    }

    // 9. Draw Hair Front / Cap
    final hairPaint = Paint()
      ..color = hairColor
      ..style = PaintingStyle.fill;

    if (hairStyle == 1) {
      final path = Path()
        ..moveTo(faceCenterX - faceRadius, faceCenterY - faceRadius * 0.2)
        ..quadraticBezierTo(faceCenterX - faceRadius * 0.9, faceCenterY - faceRadius * 0.9, faceCenterX, faceCenterY - faceRadius)
        ..quadraticBezierTo(faceCenterX + faceRadius * 0.9, faceCenterY - faceRadius * 0.9, faceCenterX + faceRadius, faceCenterY - faceRadius * 0.2)
        ..quadraticBezierTo(faceCenterX + faceRadius * 0.8, faceCenterY - faceRadius * 0.6, faceCenterX + faceRadius * 0.5, faceCenterY - faceRadius * 0.5)
        ..quadraticBezierTo(faceCenterX, faceCenterY - faceRadius * 0.8, faceCenterX - faceRadius * 0.5, faceCenterY - faceRadius * 0.5)
        ..quadraticBezierTo(faceCenterX - faceRadius * 0.8, faceCenterY - faceRadius * 0.6, faceCenterX - faceRadius, faceCenterY - faceRadius * 0.2);
      canvas.drawPath(path, hairPaint);
    } else if (hairStyle == 2) {
      canvas.drawCircle(Offset(faceCenterX - faceRadius * 0.8, faceCenterY - faceRadius * 0.6), faceRadius * 0.35, hairPaint);
      canvas.drawCircle(Offset(faceCenterX - faceRadius * 0.5, faceCenterY - faceRadius * 0.9), faceRadius * 0.4, hairPaint);
      canvas.drawCircle(Offset(faceCenterX, faceCenterY - faceRadius * 1.0), faceRadius * 0.45, hairPaint);
      canvas.drawCircle(Offset(faceCenterX + faceRadius * 0.5, faceCenterY - faceRadius * 0.9), faceRadius * 0.4, hairPaint);
      canvas.drawCircle(Offset(faceCenterX + faceRadius * 0.8, faceCenterY - faceRadius * 0.6), faceRadius * 0.35, hairPaint);
    } else if (hairStyle == 3) {
      final capColor = palette[0];
      final capPaint = Paint()..color = capColor;
      final capRect = Rect.fromCircle(center: Offset(faceCenterX, faceCenterY - faceRadius * 0.2), radius: faceRadius);
      canvas.drawArc(capRect, pi, pi, true, capPaint);
      final brimPaint = Paint()
        ..color = capColor
        ..style = PaintingStyle.fill;
      final brimPath = Path()
        ..moveTo(faceCenterX - faceRadius * 1.1, faceCenterY - faceRadius * 0.2)
        ..quadraticBezierTo(faceCenterX, faceCenterY - faceRadius * 0.35, faceCenterX + faceRadius * 1.1, faceCenterY - faceRadius * 0.2)
        ..quadraticBezierTo(faceCenterX, faceCenterY - faceRadius * 0.05, faceCenterX - faceRadius * 1.1, faceCenterY - faceRadius * 0.2);
      canvas.drawPath(brimPath, brimPaint);
    } else if (hairStyle == 4) {
      final path = Path()
        ..moveTo(faceCenterX - faceRadius, faceCenterY - faceRadius * 0.2)
        ..quadraticBezierTo(faceCenterX - faceRadius * 0.9, faceCenterY - faceRadius * 0.9, faceCenterX, faceCenterY - faceRadius)
        ..quadraticBezierTo(faceCenterX + faceRadius * 0.9, faceCenterY - faceRadius * 0.9, faceCenterX + faceRadius, faceCenterY - faceRadius * 0.2)
        ..quadraticBezierTo(faceCenterX, faceCenterY - faceRadius * 0.4, faceCenterX - faceRadius, faceCenterY - faceRadius * 0.2);
      canvas.drawPath(path, hairPaint);
    } else {
      final eyebrowPaint = Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(faceCenterX - eyeOffsetX - eyeWidth * 0.5, eyeY - eyeHeight * 0.5),
        Offset(faceCenterX - eyeOffsetX + eyeWidth * 0.5, eyeY - eyeHeight * 0.7),
        eyebrowPaint,
      );
      canvas.drawLine(
        Offset(faceCenterX + eyeOffsetX + eyeWidth * 0.5, eyeY - eyeHeight * 0.5),
        Offset(faceCenterX + eyeOffsetX - eyeWidth * 0.5, eyeY - eyeHeight * 0.7),
        eyebrowPaint,
      );
    }
  }

  int _getSeed(String name) {
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return hash.abs();
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.name != name;
  }
}
