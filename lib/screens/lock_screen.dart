import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/supabase_sync_service.dart';
import '../widgets/vault_toast.dart';

class LockScreen extends StatefulWidget {
  final bool isOverlay;
  const LockScreen({super.key, this.isOverlay = false});

  static bool isVisible = false;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _passwordCtrl = TextEditingController();
  bool _obscureText = true;
  int _dueThisMonthCount = 0;
  bool _isLoadingCount = true;
  String _errorMessage = '';
  bool _showSplash = false;
  bool _showSplashSubtitle = false;
  bool _canUseBiometrics = false;
  String _greetingName = 'LENDER';

  @override
  void initState() {
    super.initState();
    LockScreen.isVisible = true;
    _showSplash = false;
    _loadProfileName();
    _loadDueCount();
    _initBiometrics();
  }

  Future<void> _loadProfileName() async {
    try {
      final settings = await SupabaseSyncService.instance.loadProfileSettings();
      final name = settings['fullName'] as String? ?? '';
      if (mounted) {
        setState(() {
          if (name.trim().isNotEmpty) {
            _greetingName = name.trim().toUpperCase();
          } else {
            _greetingName = 'LENDER';
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _initBiometrics() async {
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    final isBiometricsEnabled = settings['isBiometricsEnabled'] ?? false;
    final canUse = await AuthService.canAuthenticate();
    if (mounted) {
      setState(() {
        _canUseBiometrics = canUse && isBiometricsEnabled;
      });
      if (isBiometricsEnabled && canUse) {
        _authenticateBiometrically();
      }
    }
  }

  Future<void> _authenticateBiometrically() async {
    final authenticated = await AuthService.authenticate(
      reason: 'Authenticate to enter ANDA Vault',
    );
    if (authenticated && mounted) {
      _grantAccess();
    }
  }

  void _grantAccess() {
    if (widget.isOverlay) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    }
  }

  Widget _buildSplash() {
    return Container(
      key: const ValueKey('splash_screen'),
      color: AppTheme.cream,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo Image with subtle fade-in/scale-in
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOut,
              builder: (context, val, child) {
                return Opacity(
                  opacity: val,
                  child: Transform.scale(
                    scale: 0.9 + (0.1 * val),
                    child: child,
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/logo.jpg',
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // "ANDA" text appearing after a slight delay
            TypewriterText(
              text: 'ANDA',
              speed: const Duration(milliseconds: 70),
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
              ),
              onComplete: () {
                if (mounted) {
                  setState(() {
                    _showSplashSubtitle = true;
                  });
                  Future.delayed(const Duration(milliseconds: 1000), () {
                    if (mounted) {
                      setState(() {
                        _showSplash = false;
                      });
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            // Smoothly faded subtitle
            AnimatedOpacity(
              opacity: _showSplashSubtitle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: const Text(
                'PERSONAL VAULT & LEDGER',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadDueCount() async {
    try {
      final count = await DatabaseHelper.instance.getDueThisMonthCount();
      if (mounted) {
        setState(() {
          _dueThisMonthCount = count;
          _isLoadingCount = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingCount = false;
        });
      }
    }
  }

  Future<void> _verifyPassword() async {
    final entered = _passwordCtrl.text;
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    final savedPassword = settings['lockPassword'] ?? 'julius';
    final savedPin = settings['paymentPin'] ?? '1234';

    if (entered == savedPassword || entered == savedPin) {
      setState(() {
        _errorMessage = '';
      });
      _grantAccess();
    } else {
      setState(() {
        _errorMessage = 'Incorrect Password or PIN. Please try again.';
      });
      if (mounted) {
        VaultToast.showError(
          context,
          _errorMessage,
        );
      }
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    LockScreen.isVisible = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEE, MMM d').format(now).toUpperCase();

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _showSplash
            ? _buildSplash()
            : Container(
                key: const ValueKey('lock_form'),
                color: AppTheme.cream,
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        // Header logo
                        const Text(
                          'ANDA',
                          style: TextStyle(
                            color: AppTheme.navy,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Hello Name (Typewriter Animated)
                        TypewriterText(
                          key: ValueKey(_greetingName),
                          text: 'HELLO\n$_greetingName',
                          style: const TextStyle(
                            color: AppTheme.navy,
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            height: 1.25,
                            letterSpacing: -0.5,
                          ),
                          speed: const Duration(milliseconds: 90),
                        ),
                        const SizedBox(height: 8),

                        // Date
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: AppTheme.textGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Navy password container
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24.0),
                          decoration: BoxDecoration(
                            color: AppTheme.navy,
                            borderRadius: BorderRadius.circular(24.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ENTER PASSWORD:',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Password input field
                              TextField(
                                controller: _passwordCtrl,
                                obscureText: _obscureText,
                                style: const TextStyle(
                                  color: AppTheme.textDark,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                onSubmitted: (_) => _verifyPassword(),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: AppTheme.white,
                                  hintText: 'Enter Password or 4-digit PIN',
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 15),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureText
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: AppTheme.textGrey,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureText = !_obscureText;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: AppTheme.yellow, width: 2.0),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Enter Vault row
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 52,
                                      child: ElevatedButton(
                                        onPressed: _verifyPassword,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.yellow,
                                          foregroundColor: AppTheme.navy,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(50),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Enter Vault',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Icon(Icons.arrow_forward, size: 18),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_canUseBiometrics) ...[
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: ElevatedButton(
                                        onPressed: _authenticateBiometrically,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.cream,
                                          foregroundColor: AppTheme.navy,
                                          elevation: 0,
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: const Icon(Icons.fingerprint, size: 28),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Notification Pill indicator
                        _isLoadingCount
                            ? const SizedBox.shrink()
                            : Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAE5DB),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.04),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: AppTheme.red,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _dueThisMonthCount > 0
                                            ? '$_dueThisMonthCount borrower${_dueThisMonthCount == 1 ? '' : 's'} ${_dueThisMonthCount == 1 ? 'is' : 'are'} due this month. Would you like to check?'
                                            : 'No borrowers are due this month.',
                                        style: const TextStyle(
                                          color: Color(0xFF4A4A4A),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        const SizedBox(height: 48),

                        // Session Footer
                        Center(
                          child: Column(
                            children: [
                              Text(
                                'SECURE SESSION',
                                style: TextStyle(
                                  color: AppTheme.textGrey.withValues(alpha: 0.8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'AES-256 Bit Encryption Active',
                                style: TextStyle(
                                  color: AppTheme.textGrey.withValues(alpha: 0.5),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// ── Typewriter Text Widget ──

class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration speed;
  final VoidCallback? onComplete;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;

  const TypewriterText({
    super.key,
    required this.text,
    required this.style,
    this.speed = const Duration(milliseconds: 100),
    this.onComplete,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = '';
  int _currentIndex = 0;
  Timer? _timer;
  bool _showCursor = true;
  Timer? _cursorTimer;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _timer?.cancel();
    _cursorTimer?.cancel();

    setState(() {
      _displayedText = '';
      _currentIndex = 0;
      _showCursor = true;
    });

    _timer = Timer.periodic(widget.speed, (timer) {
      if (_currentIndex < widget.text.length) {
        setState(() {
          _currentIndex++;
          _displayedText = widget.text.substring(0, _currentIndex);
        });
      } else {
        _timer?.cancel();
        _startCursorBlinking();
        if (widget.onComplete != null) {
          widget.onComplete!();
        }
      }
    });
  }

  void _startCursorBlinking() {
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        _showCursor = !_showCursor;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cursorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: widget.mainAxisAlignment,
      mainAxisSize: widget.mainAxisSize,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            _displayedText,
            style: widget.style,
          ),
        ),
        Text(
          _showCursor ? '_' : ' ',
          style: widget.style.copyWith(
            fontWeight: FontWeight.w300,
            color: widget.style.color?.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
