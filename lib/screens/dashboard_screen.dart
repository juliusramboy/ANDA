import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/notification_service.dart';
import 'expenses_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToBorrowers;
  const DashboardScreen({super.key, this.onNavigateToBorrowers});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  double totalValue = 0;
  double yield_ = 0;
  double remainingPrincipal = 0;
  int activeBorrowers = 0;
  int dueThisMonth = 0;
  List<Borrower> upcoming = [];
  bool loading = true;
  bool _dbToolsExpanded = false;

  @override
  void initState() {
    super.initState();
    _initNotificationsAndLoad();
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
    final tv = y + rp; // Expected Return = Profit + Remaining Principal
    final ab = await db.getActiveBorrowers();
    final up = await db.getUpcomingDueBorrowers();
    final dc = await db.getDueThisMonthCount();
    setState(() {
      totalValue = tv;
      yield_ = y;
      remainingPrincipal = rp;
      activeBorrowers = ab;
      dueThisMonth = dc;
      upcoming = up;
      loading = false;
    });

    if (dc > 0) {
      await NotificationService.showNotificationIfDue(dc);
    }
  }

  Future<void> _exportDatabase() async {
    try {
      final dbPath = await db.getDatabasePath();
      final file = File(dbPath);
      if (await file.exists()) {
        if (Platform.isAndroid) {
          final dir = Directory('/storage/emulated/0/Download');
          if (await dir.exists()) {
            final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
            final backupFileName = 'vault_backup_$timestamp.db';
            final backupFile = File('${dir.path}/$backupFileName');
            await file.copy(backupFile.path);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Backup saved to Downloads: $backupFileName'),
                  backgroundColor: AppTheme.green,
                ),
              );
            }
            return;
          }
        }
        await Share.shareXFiles([XFile(dbPath)], text: 'ANDA Database Backup');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Database file not found.'),
              backgroundColor: AppTheme.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export backup: $e'),
            backgroundColor: AppTheme.red,
          ),
        );
      }
    }
  }

  Future<void> _importDatabase() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cream,
          title: const Text(
            'Import Database Backup',
            style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Warning: This action will completely overwrite your current database. This cannot be undone.\n\nAre you sure you want to proceed?',
            style: TextStyle(color: AppTheme.textDark),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Proceed'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        
        if (mounted) {
          setState(() => loading = true);
        }

        final success = await db.importDatabase(path);

        if (success) {
          await _load();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Database backup imported successfully!'),
                backgroundColor: AppTheme.green,
              ),
            );
          }
        } else {
          if (mounted) {
            setState(() => loading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to import database. Invalid backup file or schema mismatch.'),
                backgroundColor: AppTheme.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: AppTheme.red,
          ),
        );
      }
    }
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
    final dateStr = DateFormat('EEE, MMM d').format(now);

    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Top bar ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'HELLO JULIUS • $dateStr'.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textGrey,
                              letterSpacing: 0.5,
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_horiz, color: AppTheme.textDark),
                            color: AppTheme.white,
                            surfaceTintColor: AppTheme.white,
                            onSelected: (value) {
                              if (value == 'expenses') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ExpensesScreen()),
                                ).then((_) => _load());
                              } else if (value == 'map') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const MapScreen()),
                                );
                              } else if (value == 'profile') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                                ).then((_) => _load());
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'expenses',
                                child: Row(
                                  children: [
                                    Icon(Icons.account_balance_wallet_outlined, color: AppTheme.navy, size: 20),
                                    SizedBox(width: 8),
                                    Text('Expenses', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'map',
                                child: Row(
                                  children: [
                                    Icon(Icons.map_outlined, color: AppTheme.navy, size: 20),
                                    SizedBox(width: 8),
                                    Text('Map Route', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'profile',
                                child: Row(
                                  children: [
                                    Icon(Icons.person_outline, color: AppTheme.navy, size: 20),
                                    SizedBox(width: 8),
                                    Text('Profile', style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Headline ──
                      Text(
                        dueThisMonth > 0
                            ? "Theres $dueThisMonth due date${dueThisMonth == 1 ? '' : 's'}\nin this month."
                            : 'Welcome to\nyour Vault.',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Hero card ──
                      NavyCard(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Yellow circle decoration (large, top-right, clipped)
                            Positioned(
                              right: -30,
                              top: -35,
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: const BoxDecoration(
                                  color: AppTheme.yellow,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ANDA',
                                  style: TextStyle(
                                    color: AppTheme.yellow,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      '$activeBorrowers',
                                      style: const TextStyle(
                                        color: AppTheme.white,
                                        fontSize: 72,
                                        fontWeight: FontWeight.bold,
                                        height: 1.0,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      activeBorrowers == 1 ? 'Borrower' : 'Borrowers',
                                      style: const TextStyle(
                                        color: AppTheme.yellow,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Borrowers Audit',
                                  style: TextStyle(
                                    color: AppTheme.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'App Date Build by June 12, 2026',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: widget.onNavigateToBorrowers,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.yellow,
                                          foregroundColor: AppTheme.navy,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(50),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 14,
                                          ),
                                          elevation: 0,
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Manage Borrowers',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            SizedBox(width: 6),
                                            Icon(Icons.arrow_forward, size: 16),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: _showLoanCalculator,
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2C3A5A),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppTheme.yellow,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.calculate_outlined,
                                          color: AppTheme.yellow,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _dbToolsExpanded = !_dbToolsExpanded;
                                    });
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'DATABASE TOOLS',
                                        style: TextStyle(
                                          color: AppTheme.yellow,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      Icon(
                                        _dbToolsExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        color: AppTheme.yellow,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  child: _dbToolsExpanded
                                      ? Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: ElevatedButton(
                                                    onPressed: _importDatabase,
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: AppTheme.yellow,
                                                      foregroundColor: AppTheme.navy,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(50),
                                                      ),
                                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                                      elevation: 0,
                                                    ),
                                                    child: const Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(Icons.upload, size: 16),
                                                        SizedBox(width: 6),
                                                        Text('Import Data',
                                                            style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 13)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: OutlinedButton(
                                                    onPressed: _exportDatabase,
                                                    style: OutlinedButton.styleFrom(
                                                      side: const BorderSide(color: AppTheme.yellow, width: 1.5),
                                                      foregroundColor: AppTheme.yellow,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(50),
                                                      ),
                                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                                      elevation: 0,
                                                    ),
                                                    child: const Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(Icons.download, size: 16),
                                                        SizedBox(width: 6),
                                                        Text('Export Backup',
                                                            style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 13)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: StatCard(
                              value: '₱${fmt.format(totalValue)}',
                              label: 'Expected Return',
                              sublabel:
                                  DateFormat('MMM yyyy').format(DateTime.now()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StatCard(
                              value: '₱${fmt.format(yield_)}',
                              label: 'Profit',
                              sublabel: 'Q2 Growth',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StatCard(
                        value: '₱${fmt.format(remainingPrincipal)}',
                        label: 'Remaining Principal',
                        sublabel: 'Outstanding balance across all loans',
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid positive numbers.'),
          backgroundColor: AppTheme.red,
        ),
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
