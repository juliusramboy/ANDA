import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../services/supabase_sync_service.dart';
import 'lock_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _floatController;
  late AnimationController _driftController;

  late Animation<double> _fadeAnimation;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // 1. Entrance animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );

    // 2. Continuous floating & breathing animation for tag pills
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // 3. Continuous horizontal drift animation for bottom pills
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat(reverse: true);

    _entranceController.forward();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/first_launch.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        if (data['firstLaunch'] == false) {
          if (!mounted) return;
          final settings = await SupabaseSyncService.instance.loadProfileSettings();
          final bool isLockEnabled = settings['isLockEnabled'] ?? false;
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 300),
              pageBuilder: (_, animation, __) => FadeTransition(
                opacity: animation,
                child: isLockEnabled ? const LockScreen() : const MainShell(),
              ),
            ),
          );
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _floatController.dispose();
    _driftController.dispose();
    super.dispose();
  }

  Future<void> _proceedToApp() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: const OnboardingScreen(),
        ),
      ),
    );
  }

  static const TextStyle _headlineStyle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w900,
    color: Color(0xFF14171F),
    letterSpacing: -1.2,
    height: 1.15,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),

                // ── Hero Headline with Static Inline Colored Pills ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('DITCH THE', style: _headlineStyle),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStaticInlinePill('NOTEBOOK', const Color(0xFFFFA500)),
                          const Text(' .', style: _headlineStyle),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text('LET ANDA', style: _headlineStyle),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStaticInlinePill('TRACK IT', const Color(0xFF52B76F)),
                          const Text(' ,', style: _headlineStyle),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStaticInlinePill('REMIND IT', const Color(0xFFFFA500)),
                          const Text(' ,', style: _headlineStyle),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text('AND', style: _headlineStyle),
                      const SizedBox(height: 2),
                      const Text('NEVER LET A', style: _headlineStyle),
                      const SizedBox(height: 2),
                      _buildStaticInlinePill('DUE DATE', const Color(0xFF52B76F)),
                      const SizedBox(height: 2),
                      const Text('SLIP.', style: _headlineStyle),
                    ],
                  ),
                ),

                // ── Bottom Moving / Drifting Tag Pills (Left to Right) ──
                _buildBottomMovingPillsCluster(),
                const SizedBox(height: 24),

                // ── Continue Button (Page 1 of Instructions) ──
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _proceedToApp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Static Inline Capsule Pill (Non-moving) ──
  Widget _buildStaticInlinePill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  // ── Bottom Moving Pills Cluster (3 Staggered Rows with Dual Drift) ──
  Widget _buildBottomMovingPillsCluster() {
    return AnimatedBuilder(
      animation: _driftController,
      builder: (context, child) {
        final t = _driftController.value;
        final drift1 = math.sin(t * math.pi) * 14.0 - 7.0;
        final drift2 = -math.sin(t * math.pi) * 16.0 + 8.0;
        final drift3 = math.sin(t * math.pi) * 12.0 - 6.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Borrower List, Due Dates, Payments
            Transform.translate(
              offset: Offset(drift1, 0),
              child: Row(
                children: [
                  _buildTagPill('Borrower List', const Color(0xFFA5B4FC), const Color(0xFF1E1B4B), 0.0),
                  const SizedBox(width: 8),
                  _buildTagPill('Due Dates', Colors.white, const Color(0xFF1E293B), 0.2, hasBorder: true),
                  const SizedBox(width: 8),
                  _buildTagPill('Payments', const Color(0xFFF472B6), const Color(0xFF831843), 0.4),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Row 2: Loan History, Reminders, Overdue Accounts
            Transform.translate(
              offset: Offset(drift2, 0),
              child: Row(
                children: [
                  _buildTagPill('Loan History', const Color(0xFFFDA4AF), const Color(0xFF881337), 0.3),
                  const SizedBox(width: 8),
                  _buildTagPill('Reminders', const Color(0xFFFBBF24), const Color(0xFF78350F), 0.5),
                  const SizedBox(width: 8),
                  _buildTagPill('Overdue Accounts', const Color(0xFF1E293B), Colors.white, 0.7),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Row 3: Track Location, Profit Tracker
            Transform.translate(
              offset: Offset(drift3, 0),
              child: Row(
                children: [
                  _buildTagPill('Track Location', const Color(0xFF6EE7B7), const Color(0xFF064E3B), 0.1),
                  const SizedBox(width: 8),
                  _buildTagPill('Profit Tracker', const Color(0xFF818CF8), Colors.white, 0.6),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTagPill(
    String label,
    Color bgColor,
    Color textColor,
    double phase, {
    bool hasBorder = false,
  }) {
    return AnimatedBuilder(
      animation: _floatController,
      builder: (context, child) {
        final p = (_floatController.value + phase) % 1.0;
        final bobY = math.sin(p * 2 * math.pi) * 2.5;

        return Transform.translate(
          offset: Offset(0, bobY),
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: hasBorder ? Border.all(color: const Color(0xFFE2E8F0), width: 1.2) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
