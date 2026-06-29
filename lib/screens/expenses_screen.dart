import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';
import 'log_new_expense_modal.dart';
import 'insights_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  bool _loading = true;
  List<Expense> _monthlyExpenses = [];
  double _totalExpenses = 0.0;
  double _changePercentage = 0.0;
  bool _isDecrease = true;

  // Selected date context
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  // Budget configuration
  final double _monthlyBudget = 55000.0;

  @override
  void initState() {
    super.initState();
    _initDateAndLoad();
  }

  Future<void> _initDateAndLoad() async {
    // Determine the default month/year:
    // Try to get the latest logged transaction date to display seeded data nicely.
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
    
    // Aggregate only expenses
    final thisMonthStats = await db.getMonthlyProfitAndExpenses(_selectedYear, _selectedMonth);
    final totalExp = thisMonthStats['expenses'] ?? 0.0;

    // Fetch prior month's expenses for trend comparison
    int prevMonth = _selectedMonth - 1;
    int prevYear = _selectedYear;
    if (prevMonth == 0) {
      prevMonth = 12;
      prevYear = _selectedYear - 1;
    }
    final priorMonthStats = await db.getMonthlyProfitAndExpenses(prevYear, prevMonth);
    final priorExp = priorMonthStats['expenses'] ?? 0.0;

    double change = 0.0;
    bool decreased = true;
    if (priorExp > 0) {
      if (totalExp < priorExp) {
        change = ((priorExp - totalExp) / priorExp) * 100;
        decreased = true;
      } else {
        change = ((totalExp - priorExp) / priorExp) * 100;
        decreased = false;
      }
    } else if (totalExp > 0) {
      // If there was no expense in the previous month but there is this month
      change = 100.0;
      decreased = false;
    }

    setState(() {
      _monthlyExpenses = list;
      _totalExpenses = totalExp;
      _changePercentage = change;
      _isDecrease = decreased;
      _loading = false;
    });
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

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'rent':
        return Icons.apartment;
      case 'payroll':
        return Icons.people_outline;
      case 'utilities':
        return Icons.flash_on;
      case 'marketing':
        return Icons.campaign_outlined;
      case 'software':
        return Icons.cloud_queue;
      case 'services':
        return Icons.build_circle_outlined;
      case 'investment':
        return Icons.monetization_on_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  String _formatItemDate(String dateStr) {
    try {
      final date = DateFormat('MM/dd/yyyy').parse(dateStr);
      return DateFormat('MMM dd').format(date);
    } catch (_) {
      return dateStr;
    }
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
                  if (mounted) {
                    Navigator.pop(ctx); // Close action dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Expense deleted successfully'), backgroundColor: AppTheme.green),
                    );
                    _load();
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
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Expense amount updated'), backgroundColor: AppTheme.green),
                  );
                  _load();
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

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat('MMM yyyy').format(DateTime(_selectedYear, _selectedMonth)).toUpperCase();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Expenses',
          style: TextStyle(
            color: AppTheme.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Hero Total Expenses Card ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'TOTAL EXPENSES • $monthName',
                                style: const TextStyle(
                                  color: AppTheme.textGrey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (_changePercentage > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _isDecrease ? const Color(0xFFE8F8F0) : const Color(0xFFFDEDEC),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isDecrease ? Icons.trending_down : Icons.trending_up,
                                        color: _isDecrease ? AppTheme.green : AppTheme.red,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_changePercentage.toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          color: _isDecrease ? AppTheme.green : AppTheme.red,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '₱${fmt.format(_totalExpenses)}',
                            style: const TextStyle(
                              color: AppTheme.navy,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Expense Ledger Header ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'EXPENSE LEDGER',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textGrey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const InsightsScreen()),
                            ).then((_) => _load());
                          },
                          child: const Text(
                            'VIEW ALL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37), // Elegant Gold
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Expense Ledger List ──
                    if (_monthlyExpenses.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            'No transactions recorded for this month.',
                            style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _monthlyExpenses.length,
                        separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
                        itemBuilder: (ctx, idx) {
                          final item = _monthlyExpenses[idx];
                          final isExpense = item.type == 'expense';

                          return GestureDetector(
                            onTap: () => _showExpenseActionDialog(item),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppTheme.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.01),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Circle Category Icon
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF3F4F6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _getCategoryIcon(item.category),
                                      color: AppTheme.navy,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Title & Subtitle details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textDark,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_formatItemDate(item.date)} • ${item.notes ?? item.category}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Amount & Urgent Badge
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${isExpense ? '-' : '+'}₱${fmt.format(item.amount)}',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: isExpense ? AppTheme.navy : AppTheme.green,
                                        ),
                                      ),
                                      if (item.isUrgent) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: AppTheme.yellow, width: 1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'URGENT',
                                            style: TextStyle(
                                              color: AppTheme.yellow,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ]
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 100), // Space for FAB and navbar overlapping
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddExpenseModal,
        backgroundColor: AppTheme.navy,
        foregroundColor: AppTheme.white,
        shape: const CircleBorder(),
        elevation: 4,
        child: const Icon(Icons.add, size: 24),
      ),
    );
  }
}
