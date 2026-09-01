import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/borrowers_screen.dart';
import 'screens/ledger_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/map_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/lock_screen.dart';
import 'widgets/common_widgets.dart';
import 'services/supabase_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable true edge-to-edge immersive fullscreen (hiding time, battery, system status bar)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  bool isFirstLaunch = true;
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/first_launch.json');
    if (await file.exists()) {
      final content = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      if (data['firstLaunch'] == false) {
        isFirstLaunch = false;
      }
    }
  } catch (_) {}

  bool isLockEnabled = false;
  try {
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    isLockEnabled = settings['isLockEnabled'] ?? false;
  } catch (_) {}

  // Initialize Supabase in the background
  try {
    await Supabase.initialize(
      url: 'https://hwjpjbgqmjkhbvpfjbhp.supabase.co',
      publishableKey: 'sb_publishable_HZlpzHPbF0PwxXcpf0KOZw_64lfxHsK',
    );
  } catch (e) {
    debugPrint('Supabase background initialization error: $e');
  }

  runApp(VaultApp(isFirstLaunch: isFirstLaunch, isLockEnabled: isLockEnabled));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class VaultApp extends StatefulWidget {
  final bool isFirstLaunch;
  final bool isLockEnabled;
  const VaultApp({super.key, this.isFirstLaunch = true, this.isLockEnabled = false});

  @override
  State<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends State<VaultApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else if (state == AppLifecycleState.paused) {
      try {
        final settings = await SupabaseSyncService.instance.loadProfileSettings();
        final bool lockActive = settings['isLockEnabled'] ?? false;
        if (lockActive && !LockScreen.isVisible) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => const LockScreen(isOverlay: true),
            ),
          );
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Vault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: widget.isFirstLaunch
          ? const SplashScreen()
          : (widget.isLockEnabled ? const LockScreen() : const MainShell()),
    );
  }
}

class MainShell extends StatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _index = 0;
  bool _isNavVisible = true;
  final _dashboardKey = GlobalKey<DashboardScreenState>();
  final _borrowersKey = GlobalKey<BorrowersScreenState>();
  final _ledgerKey = GlobalKey<LedgerScreenState>();
  final _expensesKey = GlobalKey<ExpensesScreenState>();
  final _mapKey = GlobalKey<MapScreenState>();

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    SupabaseSyncService.instance.syncNotifier.addListener(_refreshAllTabs);
  }

  @override
  void dispose() {
    SupabaseSyncService.instance.syncNotifier.removeListener(_refreshAllTabs);
    super.dispose();
  }

  void _refreshAllTabs() {
    if (mounted) {
      _dashboardKey.currentState?.refresh();
      _borrowersKey.currentState?.refresh();
      _ledgerKey.currentState?.refresh();
      _expensesKey.currentState?.refresh();
      _mapKey.currentState?.refresh();
    }
  }

  void setTab(int index) {
    setState(() {
      _index = index;
      _isNavVisible = true;
    });
    _refreshCurrentTab(index);
  }

  void _refreshCurrentTab(int index) {
    if (index == 0) _dashboardKey.currentState?.refresh();
    if (index == 1) _borrowersKey.currentState?.refresh();
    if (index == 2) _ledgerKey.currentState?.refresh();
    if (index == 3) _expensesKey.currentState?.refresh();
    if (index == 4) _mapKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final navBottom = bottomInset > 0 ? bottomInset + 8 : 20.0;

    final screens = [
      DashboardScreen(
        key: _dashboardKey,
        onNavigateToBorrowers: () => setTab(1),
      ),
      BorrowersScreen(key: _borrowersKey),
      LedgerScreen(
        key: _ledgerKey,
        isNavVisible: _isNavVisible,
      ),
      ExpensesScreen(
        key: _expensesKey,
        isNavVisible: _isNavVisible,
      ),
      MapScreen(
        key: _mapKey,
        isNavVisible: _isNavVisible,
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.vertical) {
                if (notification.direction == ScrollDirection.reverse) {
                  if (_isNavVisible) {
                    setState(() => _isNavVisible = false);
                  }
                } else if (notification.direction == ScrollDirection.forward) {
                  if (!_isNavVisible) {
                    setState(() => _isNavVisible = true);
                  }
                }
              }
              return false;
            },
            child: IndexedStack(
              index: _index,
              children: screens,
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            left: 16,
            right: 16,
            bottom: _isNavVisible ? navBottom : -80,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOut,
              opacity: _isNavVisible ? 1.0 : 0.0,
              child: VaultFloatingNav(
                currentIndex: _index,
                onTap: (i) {
                  setState(() {
                    _index = i;
                    _isNavVisible = true;
                  });
                  _refreshCurrentTab(i);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

