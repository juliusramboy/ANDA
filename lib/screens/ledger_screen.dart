import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../models/payment.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'log_new_expense_modal.dart';

class LedgerScreen extends StatefulWidget {
  final bool isNavVisible;
  const LedgerScreen({super.key, this.isNavVisible = true});

  @override
  State<LedgerScreen> createState() => LedgerScreenState();
}


enum _LedgerFilter { all, expenses, income, interest }

class _LedgerItem {
  final String id;
  final String title;
  final String badge;
  final String? subtitle;
  final String? notes;
  final double amount;
  final bool isNegative;
  final DateTime dateTime;
  final String timeStr;
  final _LedgerFilter category;
  final Borrower? borrower;
  final Payment? payment;
  final Expense? expense;

  _LedgerItem({
    required this.id,
    required this.title,
    required this.badge,
    this.subtitle,
    this.notes,
    required this.amount,
    required this.isNegative,
    required this.dateTime,
    required this.timeStr,
    required this.category,
    this.borrower,
    this.payment,
    this.expense,
  });
}

class LedgerScreenState extends State<LedgerScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  List<_LedgerItem> _allItems = [];
  bool _loading = true;
  _LedgerFilter _selectedFilter = _LedgerFilter.all;

  bool _isSearchOpen = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void refresh() {
    _load();
  }

  Future<void> _load() async {
    try {
      final borrowersList = await db.getAllBorrowers();
      final Map<int, Borrower> borrowerMap = {
        for (var b in borrowersList)
          if (b.id != null) b.id!: b,
      };

      final paymentsList = await db.getAllPayments();
      final expensesList = await db.getAllExpenses();

      final List<_LedgerItem> items = [];

      // 1. Convert all borrower payments into ledger items
      for (final p in paymentsList) {
        final borrower = borrowerMap[p.borrowerId];
        final borrowerName = borrower?.fullName ?? 'Borrower #${p.borrowerId}';

        final dt = _parseDateTime(p.paymentDate, p.updatedAt);
        final timeStr = _formatTime(p.updatedAt, dt);

        final badge = p.paymentType.toUpperCase();
        final isInterest = p.paymentType == 'Interest';

        items.add(_LedgerItem(
          id: 'pay_${p.id}',
          title: borrowerName,
          badge: badge,
          subtitle: borrower?.loanReference ?? 'Loan Payment',
          notes: p.notes,
          amount: p.amount,
          isNegative: isInterest ? true : false, // Display interest/outflow with - or + as in mockup
          dateTime: dt,
          timeStr: timeStr,
          category: isInterest ? _LedgerFilter.interest : _LedgerFilter.all,
          borrower: borrower,
          payment: p,
        ));
      }

      // 2. Convert all expenses and income entries into ledger items
      for (final e in expensesList) {
        final dt = _parseDateTime(e.date, e.updatedAt);
        final timeStr = _formatTime(e.updatedAt, dt);
        final isIncome = e.type == 'income';

        items.add(_LedgerItem(
          id: 'exp_${e.id}',
          title: e.name,
          badge: isIncome ? 'INCOME' : (e.category.isNotEmpty ? e.category.toUpperCase() : 'EXPENSE'),
          subtitle: e.category,
          notes: e.notes,
          amount: e.amount,
          isNegative: !isIncome,
          dateTime: dt,
          timeStr: timeStr,
          category: isIncome ? _LedgerFilter.income : _LedgerFilter.expenses,
          expense: e,
        ));
      }

      // Sort all items chronologically (newest first)
      items.sort((a, b) => b.dateTime.compareTo(a.dateTime));

      if (mounted) {
        setState(() {
          _allItems = items;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading ledger items: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  DateTime _parseDateTime(String dateStr, String? updatedAtStr) {
    if (updatedAtStr != null && updatedAtStr.isNotEmpty) {
      try {
        return DateTime.parse(updatedAtStr).toLocal();
      } catch (_) {}
    }

    try {
      final parts = dateStr.trim().split('/');
      if (parts.length == 3) {
        final month = int.parse(parts[0]);
        final day = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day, 12, 0);
      }
    } catch (_) {}

    try {
      return DateTime.parse(dateStr).toLocal();
    } catch (_) {}

    return DateTime.now();
  }

  String _formatTime(String? updatedAtStr, DateTime fallback) {
    if (updatedAtStr != null && updatedAtStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(updatedAtStr).toLocal();
        return DateFormat('hh:mm a').format(dt);
      } catch (_) {}
    }
    return DateFormat('hh:mm a').format(fallback);
  }

  String _getDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    final diff = today.difference(itemDate).inDays;

    if (diff == 0) {
      return 'TODAY, ${DateFormat('MMM d').format(date).toUpperCase()}';
    } else if (diff == 1) {
      return 'YESTERDAY, ${DateFormat('MMM d').format(date).toUpperCase()}';
    } else if (now.year == date.year) {
      return DateFormat('EEE, MMM d').format(date).toUpperCase();
    } else {
      return DateFormat('MMM d, yyyy').format(date).toUpperCase();
    }
  }

  List<_LedgerItem> get _filteredItems {
    return _allItems.where((item) {
      // 1. Filter Tab matching
      if (_selectedFilter == _LedgerFilter.expenses && item.category != _LedgerFilter.expenses) {
        return false;
      }
      if (_selectedFilter == _LedgerFilter.income && item.category != _LedgerFilter.income) {
        return false;
      }
      if (_selectedFilter == _LedgerFilter.interest && item.category != _LedgerFilter.interest) {
        return false;
      }

      // 2. Search Query matching
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = item.title.toLowerCase().contains(q);
        final matchBadge = item.badge.toLowerCase().contains(q);
        final matchSubtitle = item.subtitle?.toLowerCase().contains(q) ?? false;
        final matchNotes = item.notes?.toLowerCase().contains(q) ?? false;
        final matchAmount = item.amount.toString().contains(q);

        if (!matchTitle && !matchBadge && !matchSubtitle && !matchNotes && !matchAmount) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Map<String, List<_LedgerItem>> get _groupedItems {
    final Map<String, List<_LedgerItem>> groups = {};
    for (final item in _filteredItems) {
      final header = _getDateHeader(item.dateTime);
      if (!groups.containsKey(header)) {
        groups[header] = [];
      }
      groups[header]!.add(item);
    }
    return groups;
  }

  void _showItemDetails(_LedgerItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
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
                Text(
                  item.payment != null ? 'Payment Details' : 'Expense Details',
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: AppTheme.textDark),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F3EB),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Title / Name', item.title, isBold: true),
                  const Divider(height: 16),
                  _buildDetailRow('Type / Badge', item.badge),
                  const Divider(height: 16),
                  _buildDetailRow('Amount', 'Php ${fmt.format(item.amount)}', isBold: true),
                  const Divider(height: 16),
                  _buildDetailRow('Date & Time', '${DateFormat('MMMM d, yyyy').format(item.dateTime)} at ${item.timeStr}'),
                  if (item.notes != null && item.notes!.isNotEmpty) ...[
                    const Divider(height: 16),
                    _buildDetailRow('Notes', item.notes!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              color: AppTheme.textDark,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedItems;

    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Row ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Ledger',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                        letterSpacing: -0.5,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isSearchOpen = !_isSearchOpen;
                          if (!_isSearchOpen) {
                            _searchQuery = '';
                            _searchController.clear();
                          }
                        });
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _isSearchOpen
                              ? AppTheme.navy
                              : const Color(0xFFF3EFEA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.04),
                          ),
                        ),
                        child: Icon(
                          _isSearchOpen ? Icons.close : Icons.search_rounded,
                          color: _isSearchOpen ? Colors.white : AppTheme.textDark,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Search Input Field ──
              if (_isSearchOpen)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
                      decoration: InputDecoration(
                        hintText: 'Search by name, type, amount, notes...',
                        hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textGrey),
                        prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textGrey),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val.trim());
                      },
                    ),
                  ),
                ),

              // ── Filter Pills ──
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      _buildFilterPill('ALL', _LedgerFilter.all),
                      const SizedBox(width: 8),
                      _buildFilterPill('EXPENSES', _LedgerFilter.expenses),
                      const SizedBox(width: 8),
                      _buildFilterPill('INCOME', _LedgerFilter.income),
                      const SizedBox(width: 8),
                      _buildFilterPill('INTEREST', _LedgerFilter.interest),
                    ],
                  ),
                ),
              ),

              // ── Ledger Transaction List ──
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : grouped.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                            itemCount: grouped.keys.length,
                            itemBuilder: (context, index) {
                              final header = grouped.keys.elementAt(index);
                              final items = grouped[header]!;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                                    child: Text(
                                      header,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF94A3B8),
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  ...items.map((item) => _buildLedgerRow(item)),
                                ],
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
      // ── Floating Add Expense Button (Gold Circle with Pencil) ──
      floatingActionButton: AnimatedSlide(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        offset: Offset.zero,
        child: AnimatedPadding(
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
      ),
    );
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


  // ── Filter Pill Button ──
  Widget _buildFilterPill(String label, _LedgerFilter filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D0D12) : const Color(0xFFF1EFEA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF71717A),
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ── Ledger Transaction Row Card ──
  Widget _buildLedgerRow(_LedgerItem item) {
    Color badgeBg;
    Color badgeColor;

    switch (item.badge.toUpperCase()) {
      case 'INTEREST':
        badgeBg = const Color(0xFFFEF3C7);
        badgeColor = const Color(0xFFB45309);
        break;
      case 'PRINCIPAL':
      case 'LOAN PRINCIPAL':
        badgeBg = const Color(0xFFFFEDD5);
        badgeColor = const Color(0xFFC2410C);
        break;
      case 'INCOME':
        badgeBg = const Color(0xFFDCFCE7);
        badgeColor = const Color(0xFF15803D);
        break;
      case 'EXPENSE':
      default:
        badgeBg = const Color(0xFFFEE2E2);
        badgeColor = const Color(0xFFB91C1C);
        break;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showItemDetails(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Left Avatar / Icon
            item.borrower != null
                ? AnimatedAvatar(name: item.title, size: 44)
                : Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F0E8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: AppTheme.navy,
                      size: 22,
                    ),
                  ),
            const SizedBox(width: 14),

            // Title and Badge row
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.badge,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: badgeColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.timeStr,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Amount in Ochre Gold
            Text(
              '${item.isNegative ? '-' : '+'}₱${fmt.format(item.amount)}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFFC68A0E),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFF1EFEA),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_outlined, color: AppTheme.textGrey, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'No ledger transactions found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try adjusting your search query'
                : 'Transactions and payments will automatically appear here',
            style: const TextStyle(fontSize: 13, color: AppTheme.textGrey),
          ),
        ],
      ),
    );
  }
}
