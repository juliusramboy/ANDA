import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import '../widgets/vault_toast.dart';
import 'add_loan_screen.dart';
import 'chatbot_screen.dart';
import 'profile_screen.dart';
import '../services/supabase_sync_service.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToBorrowers;
  const DashboardScreen({super.key, this.onNavigateToBorrowers});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  double yield_ = 0;
  double remainingPrincipal = 0;
  int activeBorrowers = 0;
  int dueThisMonth = 0;
  List<Borrower> upcoming = [];
  bool loading = true;
  bool _showStats = false;
  double _profitGrowth = 0.0;

  String _cardUsername = '';
  bool _isEditingHandle = false;
  final TextEditingController _handleController = TextEditingController();
  final FocusNode _handleFocusNode = FocusNode();

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 0.0,
    );
    _flipAnimation = CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOutCubic,
    );
    _initNotificationsAndLoad();
  }

  @override
  void dispose() {
    _flipController.dispose();
    _handleController.dispose();
    _handleFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initNotificationsAndLoad() async {
    await NotificationService.init();
    await _load();
  }

  void refresh() {
    _load();
  }

  Future<void> _load() async {
    final y = await db.getTotalYield();
    final rp = await db.getTotalRemainingPrincipal();
    final ab = await db.getActiveBorrowers();
    final up = await db.getUpcomingDueBorrowers();
    final dc = await db.getDueThisMonthCount();
    final pg = await db.getProfitGrowthPercentage();
    
    // Load card username
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    final savedHandle = (settings['cardUsername'] ?? '').toString().trim();

    if (mounted) {
      setState(() {
        yield_ = y;
        remainingPrincipal = rp;
        activeBorrowers = ab;
        dueThisMonth = dc;
        upcoming = up;
        _profitGrowth = pg;
        _cardUsername = savedHandle;
        loading = false;
      });
    }

    if (dc > 0) {
      await NotificationService.showNotificationIfDue(dc);
    }
  }

  void _startEditingHandle() {
    setState(() {
      _isEditingHandle = true;
      _handleController.text = _cardUsername;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _handleFocusNode.requestFocus();
      }
    });
  }

  Future<void> _saveHandle(String newHandle) async {
    final cleanHandle = newHandle.replaceAll('@', '').trim();
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    settings['cardUsername'] = cleanHandle;
    await SupabaseSyncService.instance.saveProfileSettings(settings);

    if (mounted) {
      setState(() {
        _cardUsername = cleanHandle;
        _isEditingHandle = false;
      });
      VaultToast.showSuccess(context, 'Card username saved!');
    }
  }

  void _toggleCardFlip() {
    if (_isEditingHandle) return;
    if (_flipController.isAnimating) return;
    if (_showStats) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() {
      _showStats = !_showStats;
    });
  }

  void _showLoanCalculator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _LoanCalculatorBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEE, MMM d').format(now).toUpperCase();

    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Top Header Bar ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                              letterSpacing: -0.5,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ChatbotScreen(),
                                ),
                              );
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 16,
                                    offset: const Offset(0, 5),
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFFC68A0E).withValues(alpha: 0.15),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(
                                    Icons.chat_bubble_rounded,
                                    color: AppTheme.navy,
                                    size: 22,
                                  ),
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Hero Card (3D Flip Animation) ──
                      GestureDetector(
                        onTap: _toggleCardFlip,
                        child: AnimatedBuilder(
                          animation: _flipAnimation,
                          builder: (context, child) {
                            final angle = _flipAnimation.value * pi;
                            final isBack = angle >= pi / 2;
                            return Transform(
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0012)
                                ..rotateX(-angle),
                              alignment: Alignment.center,
                              child: isBack
                                  ? Transform(
                                      transform: Matrix4.identity()..rotateX(pi),
                                      alignment: Alignment.center,
                                      child: _buildCardContainer(_buildCardStatsState()),
                                    )
                                  : _buildCardContainer(_buildCardLogoState()),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Quick Action Buttons (Add, View, Profile) ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildCircleAction(
                            icon: Icons.add,
                            label: 'Add',
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AddLoanScreen(),
                                ),
                              );
                              _load();
                            },
                          ),
                          _buildCircleAction(
                            icon: _showStats
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            label: 'View',
                            onTap: _toggleCardFlip,
                          ),
                          _buildCircleAction(
                            icon: Icons.person_outline_rounded,
                            label: 'Profile',
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProfileScreen(),
                                ),
                              );
                              _load();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ── Interest Calculator Button (Dark Pill) ──
                      GestureDetector(
                        onTap: _showLoanCalculator,
                        child: Container(
                          width: double.infinity,
                          height: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFF18181B),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.poll_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Interest Calculator',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Profit Growth Chart Card ──
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'PROFIT GROWTH',
                                        style: TextStyle(
                                          color: Color(0xFF8C95A2),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _profitGrowth >= 0
                                              ? const Color(0xFFD1FADF)
                                              : const Color(0xFFFEE4E2),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Text(
                                          _profitGrowth >= 0
                                              ? '+${_profitGrowth.toStringAsFixed(1)}%'
                                              : '${_profitGrowth.toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            color: _profitGrowth >= 0
                                                ? const Color(0xFF037847)
                                                : const Color(0xFFD92D20),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '+₱${fmt.format(yield_)}',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'This Month',
                                    style: TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 95,
                              child: CustomPaint(
                                painter: _ProfitGrowthChartPainter(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCardContainer(Widget child) {
    return Container(
      width: double.infinity,
      height: 195,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }

  // ── Hero Card: Logo View (Front Side) ──
  Widget _buildCardLogoState() {
    return SizedBox(
      height: 147,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'ANDA',
            style: TextStyle(
              color: Color(0xFFC68A0E),
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_isEditingHandle)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC68A0E), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFC68A0E).withValues(alpha: 0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '@',
                        style: TextStyle(
                          color: Color(0xFFC68A0E),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 100,
                        height: 22,
                        child: TextField(
                          controller: _handleController,
                          focusNode: _handleFocusNode,
                          autofocus: true,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                          decoration: const InputDecoration(
                            hintText: 'username',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.normal,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (val) => _saveHandle(val),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _saveHandle(_handleController.text),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFFC68A0E),
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                )
              else
                GestureDetector(
                  onTap: _startEditingHandle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _cardUsername.isEmpty
                          ? const Color(0xFFC68A0E).withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: _cardUsername.isEmpty
                          ? Border.all(
                              color: const Color(0xFFC68A0E).withValues(alpha: 0.3),
                              width: 1,
                            )
                          : null,
                    ),
                    child: _cardUsername.isNotEmpty
                        ? Text(
                            '@$_cardUsername',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '@',
                                style: TextStyle(
                                  color: Color(0xFFC68A0E),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.edit_outlined,
                                color: Color(0xFFC68A0E),
                                size: 13,
                              ),
                            ],
                          ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Hero Card: Stats View (Back Side) ──
  Widget _buildCardStatsState() {
    return SizedBox(
      height: 147,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$activeBorrowers',
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFC68A0E),
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UNPAID',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFC68A0E),
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    'BORROWERS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFC68A0E),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '₱${fmt.format(remainingPrincipal)}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFC68A0E),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'REMAINING PRINCIPAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFC68A0E),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/logo.jpg',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Circle Action Item (Add, View, Profile) ──
  Widget _buildCircleAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 26,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Custom Painter for the Smooth Profit Growth Chart ──
class _ProfitGrowthChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Control points for the bezier wave matching mockup
    final path = Path();
    path.moveTo(0, h * 0.95);
    
    // Wave 1: First crest
    path.cubicTo(
      w * 0.20, h * 0.65,
      w * 0.32, h * 0.65,
      w * 0.45, h * 0.82,
    );

    // Wave 2: Valley and swoop up to final peak
    path.cubicTo(
      w * 0.58, h * 0.96,
      w * 0.72, h * 0.28,
      w * 0.94, h * 0.28,
    );

    // Continue to right edge
    path.lineTo(w, h * 0.32);

    // Area Fill Path
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFEADBCA),
          Color(0xFFF2E7D7),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(fillPath, fillPaint);

    // Stroke Path
    final strokePaint = Paint()
      ..color = const Color(0xFF1B2A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);

    // Dot at peak
    final dotPaint = Paint()..color = const Color(0xFFC68A0E);
    canvas.drawCircle(Offset(w * 0.94, h * 0.28), 4.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Loan Calculator Bottom Sheet (Retained Feature) ──
class _LoanCalculatorBottomSheet extends StatefulWidget {
  const _LoanCalculatorBottomSheet();

  @override
  State<_LoanCalculatorBottomSheet> createState() => _LoanCalculatorBottomSheetState();
}

class _LoanCalculatorBottomSheetState extends State<_LoanCalculatorBottomSheet> {
  final _amountCtrl = TextEditingController(text: '10,000');
  final _durationCtrl = TextEditingController(text: '2');
  double _selectedRate = 10.0;

  double? _calculatedMonthlyInterest;
  double? _calculatedTotalInterest;
  double? _calculatedMaturityBalance;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final amountText = _amountCtrl.text.replaceAll(',', '').trim();
    final durationText = _durationCtrl.text.trim();

    final principal = double.tryParse(amountText) ?? 0.0;
    final months = int.tryParse(durationText) ?? 0;

    if (principal <= 0 || months <= 0) {
      VaultToast.showError(
        context,
        'Please enter valid positive numbers.',
      );
      return;
    }

    setState(() {
      _calculatedMonthlyInterest = principal * (_selectedRate / 100);
      _calculatedTotalInterest = _calculatedMonthlyInterest! * months;
      _calculatedMaturityBalance = principal + _calculatedTotalInterest!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Loan Calculator',
                  style: TextStyle(
                    color: AppTheme.navy,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppTheme.textDark, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'LOAN AMOUNT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textGrey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF4EFEB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textDark,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'MONTHLY INTEREST RATE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textGrey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [5.0, 10.0, 15.0, 20.0].map((rate) {
                final isSelected = _selectedRate == rate;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRate = rate;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.navy : const Color(0xFFF4EFEB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${rate.toInt()}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppTheme.white : AppTheme.textDark,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'DURATION (MONTHS)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textGrey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF4EFEB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _durationCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textDark,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _calculate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.navy,
                  foregroundColor: AppTheme.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: const Text(
                  'Calculate Interest',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (_calculatedMonthlyInterest != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EFEB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CALCULATION RESULTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textGrey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Divider(height: 20, color: Colors.black12),
                    _buildResultRow('Monthly Interest:', 'Php ${_formatDouble(_calculatedMonthlyInterest!)}'),
                    const SizedBox(height: 8),
                    _buildResultRow('Total Interest:', 'Php ${_formatDouble(_calculatedTotalInterest!)}'),
                    const SizedBox(height: 8),
                    _buildResultRow('Maturity Balance:', 'Php ${_formatDouble(_calculatedMaturityBalance!)}', isBold: true),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: AppTheme.textDark,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isBold ? AppTheme.navy : AppTheme.textDark,
          ),
        ),
      ],
    );
  }

  String _formatDouble(double val) {
    return NumberFormat('#,##0.00').format(val);
  }
}
