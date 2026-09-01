import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';
import '../services/supabase_sync_service.dart';
import 'log_new_expense_modal.dart';

class ExpensesScreen extends StatefulWidget {
  final bool isNavVisible;
  const ExpensesScreen({super.key, this.isNavVisible = true});

  @override
  State<ExpensesScreen> createState() => ExpensesScreenState();
}

class ExpensesScreenState extends State<ExpensesScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  void refresh() {
    _load();
  }

  bool _loading = true;
  List<Expense> _monthlyExpenses = [];
  double _monthlyProfit = 0.0;
  double _totalSpent = 0.0;
  double _remainingLeft = 0.0;
  double _spentPercentage = 0.0;
  double _remainingPercentage = 100.0;
  List<double> _weeklySpends = [0.0, 0.0, 0.0, 0.0];

  // Interactive Week Filter: null = All weeks, 0 = W1, 1 = W2, 2 = W3, 3 = W4
  int? _selectedWeekIndex;

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  List<Expense> get _filteredExpenses {
    if (_selectedWeekIndex == null) return _monthlyExpenses;
    return _monthlyExpenses.where((exp) {
      if (exp.type != 'expense') return false;
      try {
        final parts = exp.date.split('/');
        if (parts.length == 3) {
          final day = int.parse(parts[1]);
          if (_selectedWeekIndex == 0) return day >= 1 && day <= 7;
          if (_selectedWeekIndex == 1) return day >= 8 && day <= 14;
          if (_selectedWeekIndex == 2) return day >= 15 && day <= 21;
          if (_selectedWeekIndex == 3) return day >= 22;
        }
      } catch (_) {}
      return false;
    }).toList();
  }

  String _getWeekDateRange(int index) {
    switch (index) {
      case 0:
        return '1–7';
      case 1:
        return '8–14';
      case 2:
        return '15–21';
      case 3:
      default:
        return '22–End';
    }
  }

  @override
  void initState() {
    super.initState();
    _initDateAndLoad();
  }

  Future<void> _initDateAndLoad() async {
    final all = await db.getAllExpenses();
    if (all.isNotEmpty) {
      final latest = all.first;
      try {
        final parts = latest.date.split('/');
        if (parts.length == 3) {
          _selectedMonth = int.parse(parts[0]);
          _selectedYear = int.parse(parts[2]);
        }
      } catch (_) {}
    } else {
      _selectedMonth = DateTime.now().month;
      _selectedYear = DateTime.now().year;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Fetch this month's transactions
    final list = await db.getExpensesForMonth(_selectedYear, _selectedMonth);

    // Fetch profit & expenses stats
    final stats = await db.getMonthlyProfitAndExpenses(_selectedYear, _selectedMonth);
    final profit = stats['profit'] ?? 0.0;
    final expenses = stats['expenses'] ?? 0.0;

    final left = max(0.0, profit - expenses);

    double spentPct = 0.0;
    double remPct = 100.0;

    if (profit > 0) {
      spentPct = min(100.0, (expenses / profit) * 100.0);
      remPct = max(0.0, 100.0 - spentPct);
    } else if (expenses > 0) {
      spentPct = 100.0;
      remPct = 0.0;
    }

    // Calculate weekly spend pattern (W1: 1-7, W2: 8-14, W3: 15-21, W4: 22-31)
    final weekly = [0.0, 0.0, 0.0, 0.0];
    for (final exp in list) {
      if (exp.type == 'expense') {
        try {
          final parts = exp.date.split('/');
          if (parts.length == 3) {
            final day = int.parse(parts[1]);
            if (day <= 7) {
              weekly[0] += exp.amount;
            } else if (day <= 14) {
              weekly[1] += exp.amount;
            } else if (day <= 21) {
              weekly[2] += exp.amount;
            } else {
              weekly[3] += exp.amount;
            }
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _monthlyExpenses = list;
        _monthlyProfit = profit;
        _totalSpent = expenses;
        _remainingLeft = left;
        _spentPercentage = spentPct;
        _remainingPercentage = remPct;
        _weeklySpends = weekly;
        _loading = false;
      });
    }
  }

  void _showAddExpenseModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LogNewExpenseModal(
        onExpenseLogged: _load,
      ),
    );
  }

  String _formatExpenseTimestamp(Expense item) {
    try {
      final now = DateTime.now();
      final parts = item.date.split('/');
      if (parts.length == 3) {
        final month = int.parse(parts[0]);
        final day = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        final dt = DateTime(year, month, day);

        String datePrefix;
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
          datePrefix = 'Today';
        } else if (dt.year == now.year && dt.month == now.month && dt.day == now.day - 1) {
          datePrefix = 'Yesterday';
        } else {
          datePrefix = DateFormat('MMM d').format(dt);
        }

        // Check if item has time in notes or updatedAt
        if (item.notes != null && item.notes!.toLowerCase().contains('pm') || item.notes != null && item.notes!.toLowerCase().contains('am')) {
          return '$datePrefix • ${item.notes}';
        }

        return '$datePrefix • ${item.category}';
      }
    } catch (_) {}
    return item.date;
  }

  void _showExpenseActionDialog(Expense item) {
    showDialog(
      context: context,
      builder: (ctx) {
        final amountCtrl = TextEditingController(text: item.amount.toStringAsFixed(2));
        final formKey = GlobalKey<FormState>();
        return AlertDialog(
          backgroundColor: AppTheme.cream,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Manage Expense',
            style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Date: ${item.date} • Category: ${item.category}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
                ),
                const SizedBox(height: 16),
                const Text(
                  'EDIT AMOUNT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textGrey, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.lightGrey),
                  ),
                  child: TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Required';
                      final numVal = double.tryParse(val.replaceAll(',', ''));
                      if (numVal == null || numVal <= 0) return 'Invalid amount';
                      return null;
                    },
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    decoration: const InputDecoration(
                      prefixIcon: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Text('₱', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (confirmCtx) => AlertDialog(
                    backgroundColor: AppTheme.cream,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Delete Expense?', style: TextStyle(color: AppTheme.red, fontWeight: FontWeight.bold)),
                    content: Text('Are you sure you want to delete "${item.name}"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(confirmCtx, true),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red, foregroundColor: Colors.white),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await db.deleteExpense(item.id!);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    _load();
                    SupabaseSyncService.instance.syncWithFeedback(
                      context,
                      actionName: 'Expense',
                    );
                  }
                }
              },
              child: const Text('Delete', style: TextStyle(color: AppTheme.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final newAmount = double.parse(amountCtrl.text.replaceAll(',', ''));
                final updated = item.copyWith(amount: newAmount);
                await db.updateExpense(updated);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  _load();
                  SupabaseSyncService.instance.syncWithFeedback(
                    context,
                    actionName: 'Expense',
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.navy, foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  String _getMonthShortName(int month) {
    const names = [
      'Jan.', 'Feb.', 'Mar.', 'Apr.', 'May.', 'Jun.',
      'Jul.', 'Aug.', 'Sep.', 'Oct.', 'Nov.', 'Dec.'
    ];
    return names[month - 1];
  }

  String _getMonthFullName(int month) {
    const fullNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return fullNames[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Top Header: Month Dropdown Selector & Remaining Balance ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Month Selector Dropdown
                          PopupMenuButton<int>(
                            elevation: 12,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            color: Colors.white,
                            surfaceTintColor: Colors.white,
                            offset: const Offset(0, 42),
                            onSelected: (m) {
                              setState(() {
                                _selectedMonth = m;
                              });
                              _load();
                            },
                            itemBuilder: (context) {
                              return List.generate(12, (index) {
                                final m = index + 1;
                                final isSelected = m == _selectedMonth;
                                return PopupMenuItem<int>(
                                  value: m,
                                  child: Text(
                                    'Month of ${_getMonthFullName(m)}',
                                    style: TextStyle(
                                      fontFamily: 'serif',
                                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                                      fontSize: 15,
                                      color: isSelected ? const Color(0xFFC68A0E) : AppTheme.textDark,
                                    ),
                                  ),
                                );
                              });
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Month of ${_getMonthShortName(_selectedMonth)}',
                                  style: const TextStyle(
                                    fontFamily: 'serif',
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textDark,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 22,
                                  color: AppTheme.textDark,
                                ),
                              ],
                            ),
                          ),

                          // Remaining Amount Left
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₱${fmt.format(_remainingLeft)}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFC68A0E),
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const Text(
                                'LEFT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ── Spent vs Remaining Split Progress Bar ──
                      _buildSpentRemainingBar(),

                      const SizedBox(height: 20),

                      // ── Monthly Profit vs Total Spent Stats Row ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Monthly Profit',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₱${fmt.format(_monthlyProfit)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Total Spent',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₱${fmt.format(_totalSpent)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      const Divider(height: 1, color: Colors.black12),
                      const SizedBox(height: 20),

                      // ── WEEKLY SPEND PATTERN Bar Chart Header ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'WEEKLY SPEND PATTERN',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF64748B),
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _selectedWeekIndex != null
                                    ? 'Showing Week ${_selectedWeekIndex! + 1} (Days ${_getWeekDateRange(_selectedWeekIndex!)})'
                                    : 'Tap any week bar to filter',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedWeekIndex != null
                                      ? const Color(0xFFC68A0E)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                          if (_selectedWeekIndex != null)
                            GestureDetector(
                              onTap: () => setState(() => _selectedWeekIndex = null),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFC68A0E).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.close_rounded, size: 13, color: Color(0xFFC68A0E)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Show All',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFC68A0E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildWeeklySpendChart(),

                      const SizedBox(height: 26),

                      // ── ACTIVITY Section ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedWeekIndex != null
                                ? 'WEEK ${_selectedWeekIndex! + 1} EXPENSES (${_filteredExpenses.length})'
                                : 'EXPENSES ACTIVITY (${_monthlyExpenses.length})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.6,
                            ),
                          ),
                          if (_selectedWeekIndex != null)
                            Text(
                              '₱${fmt.format(_weeklySpends[_selectedWeekIndex!])}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFC68A0E),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      if (_filteredExpenses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Column(
                              children: [
                                Text(
                                  _selectedWeekIndex != null
                                      ? 'No expenses recorded for Week ${_selectedWeekIndex! + 1}.'
                                      : 'No expenses recorded for this month.',
                                  style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
                                ),
                                if (_selectedWeekIndex != null) ...[
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () => setState(() => _selectedWeekIndex = null),
                                    child: const Text('View All Weeks', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC68A0E))),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredExpenses.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final item = _filteredExpenses[index];
                            return _buildActivityItem(item);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),

      // ── Floating Add Expense Button (Gold Circle with Pencil) ──
      floatingActionButton: AnimatedPadding(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        padding: EdgeInsets.only(bottom: widget.isNavVisible ? 76 : 14),
        child: GestureDetector(
          onTap: _showAddExpenseModal,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFC68A0E),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC68A0E).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.edit_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  // ── Split Spent vs Remaining Bar ──
  Widget _buildSpentRemainingBar() {
    final spentFactor = (_spentPercentage / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFF1F5F9),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Labels: Spent % vs Remaining %
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFC68A0E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_spentPercentage.toStringAsFixed(0)}% Spent',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF94A3B8),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_remainingPercentage.toStringAsFixed(0)}% Remaining',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Continuous Progress Track
          Container(
            height: 12,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: spentFactor,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFC68A0E),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Bottom Amounts: Total Spent vs Remaining Left
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₱${fmt.format(_totalSpent)} spent',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                '₱${fmt.format(_remainingLeft)} balance',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC68A0E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Weekly Spend Pattern Bar Chart (Interactive with Smooth Height & Selection Animations) ──
  Widget _buildWeeklySpendChart() {
    final maxSpend = _weeklySpends.reduce(max);
    int peakIndex = 0;
    double highest = -1;
    for (int i = 0; i < _weeklySpends.length; i++) {
      if (_weeklySpends[i] > highest) {
        highest = _weeklySpends[i];
        peakIndex = i;
      }
    }

    const double chartMaxBarHeight = 110.0;

    return SizedBox(
      height: chartMaxBarHeight + 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (index) {
          final spend = _weeklySpends[index];
          final isSelected = _selectedWeekIndex == index;
          final isPeak = index == peakIndex && spend > 0;
          final hasFilter = _selectedWeekIndex != null;

          double barHeight = 22.0;
          if (maxSpend > 0) {
            barHeight = 22.0 + ((spend / maxSpend) * (chartMaxBarHeight - 22.0));
          } else if (index == 2) {
            barHeight = chartMaxBarHeight * 0.75;
          } else {
            barHeight = chartMaxBarHeight * 0.35 + (index * 10);
          }

          // Format amount string
          String amountStr = '₱0';
          if (spend >= 1000) {
            amountStr = '₱${(spend / 1000).toStringAsFixed(spend % 1000 == 0 ? 0 : 1)}k';
          } else if (spend > 0) {
            amountStr = '₱${spend.toInt()}';
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                if (_selectedWeekIndex == index) {
                  _selectedWeekIndex = null;
                } else {
                  _selectedWeekIndex = index;
                }
              });
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Top Amount Badge Indicator
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  opacity: (isSelected || (!hasFilter && isPeak)) ? 1.0 : (spend > 0 ? 0.70 : 0.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: isSelected
                        ? BoxDecoration(
                            color: const Color(0xFFC68A0E),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFC68A0E).withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          )
                        : null,
                    child: Text(
                      amountStr,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                        color: isSelected ? Colors.white : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),

                // Animated Bar Height & Color
                AnimatedContainer(
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  width: 64,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFC68A0E)
                        : (isPeak && !hasFilter)
                            ? const Color(0xFFC68A0E)
                            : (hasFilter ? const Color(0xFFEBE8E0).withValues(alpha: 0.6) : const Color(0xFFE8E5DD)),
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(color: const Color(0xFF9A6B0A), width: 1.5)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFFC68A0E).withValues(alpha: 0.40),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(height: 6),

                // Bottom Week Pill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFC68A0E).withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'W${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w900
                              : (isPeak && !hasFilter)
                                  ? FontWeight.w800
                                  : FontWeight.bold,
                          color: isSelected
                              ? const Color(0xFFC68A0E)
                              : (isPeak && !hasFilter)
                                  ? AppTheme.textDark
                                  : const Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        _getWeekDateRange(index),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? const Color(0xFFC68A0E) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Activity Row Item ──
  Widget _buildActivityItem(Expense item) {
    final isExpense = item.type == 'expense';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showExpenseActionDialog(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatExpenseTimestamp(item),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Text(
              '${isExpense ? '-' : '+'}₱${fmt.format(item.amount)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: isExpense ? const Color(0xFF0F172A) : const Color(0xFF16A34A),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
