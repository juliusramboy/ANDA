import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/borrowers_screen.dart';
import 'screens/ledger_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding_screen.dart';
import 'widgets/common_widgets.dart';

void main() {
  runApp(const VaultApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class VaultApp extends StatefulWidget {
  const VaultApp({super.key});

  @override
  State<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends State<VaultApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!LockScreen.isVisible) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => const LockScreen(isOverlay: true),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Vault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const LaunchDecider(),
    );
  }
}

class LaunchDecider extends StatefulWidget {
  const LaunchDecider({super.key});

  @override
  State<LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<LaunchDecider> {
  bool _checking = true;
  bool _isFirstLaunch = true;

  @override
  void initState() {
    super.initState();
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
          setState(() {
            _isFirstLaunch = false;
            _checking = false;
          });
          return;
        }
      }
    } catch (_) {}
    setState(() {
      _isFirstLaunch = true;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppTheme.cream,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_isFirstLaunch) {
      return const OnboardingScreen();
    }
    return const LockScreen();
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final List<Widget> _screens;
  final _dashboardKey = GlobalKey<DashboardScreenState>();
  final _ledgerKey = GlobalKey<LedgerScreenState>();

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardScreen(
        key: _dashboardKey,
        onNavigateToBorrowers: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BorrowersScreen()),
          );
          _dashboardKey.currentState?.refresh();
          _ledgerKey.currentState?.refresh();
        },
      ),
      LedgerScreen(key: _ledgerKey),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: _screens,
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: VaultFloatingNav(
                currentIndex: _index,
                onTap: (i) {
                  setState(() => _index = i);
                  _dashboardKey.currentState?.refresh();
                  _ledgerKey.currentState?.refresh();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
