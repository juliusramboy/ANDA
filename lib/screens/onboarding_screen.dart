import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import 'lock_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingSlide> _slides = [
    OnboardingSlide(
      title: 'Welcome to ANDA',
      subtitle: 'PERSONAL VAULT & LEDGER',
      description: 'Your ultimate cashflow manager. Safely audit active loans, track payment collections, and keep control of your expenses.',
      icon: Icons.wallet_membership_outlined,
      color: AppTheme.navy,
    ),
    OnboardingSlide(
      title: 'Expected Return',
      subtitle: 'DYNAMIC CASHFLOW OVERVIEW',
      description: 'See your real worth instantly. Calculated as Profit + Remaining Principal, representing the total value of your outstanding and completed loans.',
      icon: Icons.dashboard_customize_outlined,
      color: AppTheme.navy,
    ),
    OnboardingSlide(
      title: 'Borrowers Audit',
      subtitle: 'EASY REPAYMENT MANAGEMENT',
      description: 'Keep track of active, overdue, and fully paid loans. Easily charge custom late penalties, waive dates, and log partial or full payments.',
      icon: Icons.people_alt_outlined,
      color: AppTheme.navy,
    ),
    OnboardingSlide(
      title: 'Expenses Tracker',
      subtitle: 'COMPLETE COST CONTROL',
      description: 'Log and organize business operations expenses. Edit amounts or delete incorrect records instantly to keep your accounts accurate.',
      icon: Icons.account_balance_wallet_outlined,
      color: AppTheme.navy,
    ),
    OnboardingSlide(
      title: 'Insights & Charts',
      subtitle: 'PERFORMANCE ANALYTICS',
      description: 'Visualize profit vs. expenses with a weekly trend line graph. Keep a bird\'s-eye view of your profit growth month by month.',
      icon: Icons.analytics_outlined,
      color: AppTheme.navy,
    ),
    OnboardingSlide(
      title: 'Smart Collection Route',
      subtitle: 'OPTIMIZE YOUR TRAVELS',
      description: 'Pin collection stops, plan routes, and track live GPS location. Click Done on confirmation to clear overlays for full navigation focus.',
      icon: Icons.map_outlined,
      color: AppTheme.navy,
    ),
  ];

  Future<void> _completeOnboarding() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/first_launch.json');
      await file.writeAsString(jsonEncode({'firstLaunch': false}));
    } catch (_) {}

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LockScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ANDA',
                    style: TextStyle(
                      color: AppTheme.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      letterSpacing: 1,
                    ),
                  ),
                  if (!isLastPage)
                    TextButton(
                      onPressed: _completeOnboarding,
                      child: const Text(
                        'SKIP',
                        style: TextStyle(
                          color: AppTheme.textGrey,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Carousel Slides
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Slide Icon Card with nice visual weight
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: AppTheme.navy,
                            borderRadius: BorderRadius.circular(36),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.navy.withOpacity(0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            slide.icon,
                            color: AppTheme.yellow,
                            size: 64,
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Subtitle
                        Text(
                          slide.subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.yellow,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Title
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.navy,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Description
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            slide.description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.textDark,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Navigation Controls Footer
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Indicators Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 6,
                        width: isActive ? 20 : 6,
                        decoration: BoxDecoration(
                          color: isActive ? AppTheme.navy : AppTheme.lightGrey,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),

                  // Button Action
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        if (isLastPage) {
                          _completeOnboarding();
                        } else {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.navy,
                        foregroundColor: AppTheme.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLastPage ? 'GET STARTED' : 'CONTINUE',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isLastPage ? Icons.check_circle : Icons.arrow_forward,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingSlide {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;

  OnboardingSlide({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
  });
}
