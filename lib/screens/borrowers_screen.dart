import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'borrower_detail_screen.dart';
import 'add_loan_screen.dart';
import 'record_payment_modal.dart';

class BorrowersScreen extends StatefulWidget {
  const BorrowersScreen({super.key});

  @override
  State<BorrowersScreen> createState() => BorrowersScreenState();
}

class BorrowersScreenState extends State<BorrowersScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  void refresh() {
    _load();
  }

  List<Borrower> allBorrowers = [];
  List<Borrower> dueBorrowers = [];
  List<Borrower> recentBorrowers = [];
  List<Borrower> filteredBorrowers = [];

  bool loading = true;
  bool isAlertDismissed = false;

  final searchCtrl = TextEditingController();
  bool searching = false;

  late PageController _duePageController;
  late PageController _recentPageController;

  @override
  void initState() {
    super.initState();
    _duePageController = PageController(initialPage: 1000);
    _recentPageController = PageController(viewportFraction: 0.38, initialPage: 1000);
    _load();
    searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    _duePageController.dispose();
    _recentPageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await db.getAllBorrowers();

    // 1. Due Borrowers: Active borrowers sorted by closest repayment date
    final active = all.where((b) => b.status == 'active').toList();
    active.sort((a, b) {
      final dateA = _parseRepaymentDate(a.repaymentDate);
      final dateB = _parseRepaymentDate(b.repaymentDate);
      return dateA.compareTo(dateB);
    });

    // 2. Recent Borrowers: Sorted by ID / Issue Date descending
    final recents = List<Borrower>.from(all);
    recents.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

    if (mounted) {
      setState(() {
        allBorrowers = all;
        dueBorrowers = active.isNotEmpty ? active : all;
        recentBorrowers = recents;
        filteredBorrowers = all;
        loading = false;
      });
    }
  }

  DateTime _parseRepaymentDate(String dateStr) {
    try {
      final parts = dateStr.trim().split('/');
      if (parts.length == 3) {
        final month = int.parse(parts[0]);
        final day = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (_) {}
    try {
      return DateTime.parse(dateStr.trim());
    } catch (_) {}
    return DateTime(2099);
  }

  void _filter() {
    final q = searchCtrl.text.toLowerCase().trim();
    setState(() {
      filteredBorrowers = allBorrowers
          .where((b) =>
              b.fullName.toLowerCase().contains(q) ||
              b.loanReference.toLowerCase().contains(q))
          .toList();
    });
  }

  String _getDueStatusText(Borrower b) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = _parseRepaymentDate(b.repaymentDate);
    final diff = dueDate.difference(today).inDays;

    if (diff < 0) {
      return 'Overdue by ${-diff} day${-diff == 1 ? '' : 's'} (${b.repaymentDate})';
    } else if (diff == 0) {
      return 'Due Today (${b.repaymentDate})';
    } else if (diff == 1) {
      return 'Due tomorrow (${b.repaymentDate})';
    } else {
      return 'Due in $diff days (${b.repaymentDate})';
    }
  }

  void _showBorrowerQuickActions(Borrower b) {
    showModalBottomSheet(
      context: context,
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
              children: [
                AnimatedAvatar(name: b.fullName, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.fullName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.navy,
                        ),
                      ),
                      Text(
                        b.loanReference,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: AppTheme.textDark),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.payment, color: AppTheme.navy),
              title: const Text('Record Payment', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(ctx);
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => RecordPaymentModal(
                    borrower: b,
                  ),
                );
                _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: AppTheme.navy),
              title: const Text('View Full Contract', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(ctx);
                PdfService.viewContract(context, b);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppTheme.navy),
              title: const Text('Edit Loan Agreement', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddLoanScreen(existing: b)),
                );
                _load();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      // ── Top Bar with Back & Search ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (Navigator.canPop(context))
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3EFEA),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.arrow_back_ios_new,
                                  size: 18,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            )
                          else
                            const Text(
                              'Borrowers',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textDark,
                                letterSpacing: -0.5,
                              ),
                            ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => searching = !searching),
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: searching ? AppTheme.navy : const Color(0xFFF3EFEA),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    searching ? Icons.close : Icons.search_rounded,
                                    size: 20,
                                    color: searching ? Colors.white : AppTheme.textDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const AddLoanScreen()),
                                  );
                                  _load();
                                },
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: AppTheme.navy,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      if (searching) ...[
                        const SizedBox(height: 14),
                        Container(
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
                            controller: searchCtrl,
                            autofocus: true,
                            style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
                            decoration: InputDecoration(
                              hintText: 'Search borrowers by name or loan reference...',
                              hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textGrey),
                              prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textGrey),
                              suffixIcon: searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () {
                                        searchCtrl.clear();
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // ── Big Profile Card (Due Borrower Book / Stack / Carousel) ──
                      if (dueBorrowers.isNotEmpty)
                        SizedBox(
                          height: 250,
                          child: PageView.builder(
                            controller: _duePageController,
                            itemBuilder: (context, index) {
                              final b = dueBorrowers[index % dueBorrowers.length];
                              return _buildDueBorrowerCard(b);
                            },
                          ),
                        )
                      else
                        _buildEmptyDueCard(),

                      const SizedBox(height: 16),

                      // ── Nearly Due Alert Banner ──
                      if (!isAlertDismissed && dueBorrowers.isNotEmpty)
                        _buildNearlyDueBanner(dueBorrowers.first),

                      const SizedBox(height: 24),

                      // ── Section Header ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            searching ? 'Search Results' : 'Borrowers Directory',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                            ),
                          ),
                          Text(
                            '${filteredBorrowers.length} account${filteredBorrowers.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // ── 3-Column Scrollable Borrowers Grid (3 Boxes Per Row) ──
                      if (filteredBorrowers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: Text(
                              'No borrowers found.',
                              style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
                            ),
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: filteredBorrowers.length,
                          itemBuilder: (ctx, i) {
                            final b = filteredBorrowers[i];
                            return _BorrowerGridTile3Col(
                              borrower: b,
                              fmt: fmt,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BorrowerDetailScreen(borrowerId: b.id!),
                                  ),
                                );
                                _load();
                              },
                              onLongPress: () {
                                _showBorrowerQuickActions(b);
                              },
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ── Big Profile Card with Contract Sneak Peak ──
  Widget _buildDueBorrowerCard(Borrower b) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ── Contract Sneak Peak Background ──
          Positioned.fill(
            child: Opacity(
              opacity: 0.85,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                color: const Color(0xFFF9F6F0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'PROMISSORY NOTE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.black.withValues(alpha: 0.25),
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(width: 44), // space for expand button
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '"Agreement") is entered into and made effective as of ${b.issueDate}, by and between ANDA and ${b.fullName}, under the loan terms and covenants detailed...',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.black.withValues(alpha: 0.28),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 1,
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ISSUE DATE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black.withValues(alpha: 0.25))),
                        Text('${b.interestRate}% RATE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black.withValues(alpha: 0.25))),
                        Text('PHP ${fmt.format(b.amountBorrowed)}', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black.withValues(alpha: 0.25))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Upper Right Expand Button (Full Show Contract) ──
          Positioned(
            top: 14,
            right: 14,
            child: GestureDetector(
              onTap: () {
                PdfService.viewContract(context, b);
              },
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.crop_free_rounded,
                  color: Color(0xFF64748B),
                  size: 19,
                ),
              ),
            ),
          ),

          // ── Bottom Foreground Card Content ──
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Borrower Avatar + Name + Due Date Row
                Row(
                  children: [
                    AnimatedAvatar(name: b.fullName, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE53E3E),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _getDueStatusText(b),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE53E3E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Actions Row: Check Info & More Button
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BorrowerDetailScreen(borrowerId: b.id!),
                            ),
                          );
                          _load();
                        },
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC68A0E),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFC68A0E).withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Check Info',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _showBorrowerQuickActions(b),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F2EA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
                        ),
                        child: const Icon(
                          Icons.more_horiz,
                          color: AppTheme.textDark,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDueCard() {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
      ),
      child: const Center(
        child: Text(
          'No upcoming due borrowers at this time.',
          style: TextStyle(color: AppTheme.textGrey),
        ),
      ),
    );
  }

  // ── Nearly Due Alert Banner ──
  Widget _buildNearlyDueBanner(Borrower firstDue) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = _parseRepaymentDate(firstDue.repaymentDate);
    final diff = dueDate.difference(today).inDays;

    final dueText = diff <= 0
        ? "payment is due today (${firstDue.repaymentDate})."
        : "payment is due in $diff day${diff == 1 ? '' : 's'} (${firstDue.repaymentDate}).";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD1CF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFFE53E3E),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${dueBorrowers.length} Borrower${dueBorrowers.length == 1 ? '' : 's'} Nearly Due',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E1E24),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${firstDue.fullName}'s $dueText",
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF71717A),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                isAlertDismissed = true;
              });
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 16,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 3-Column Borrower Grid Tile (3 Boxes Per Row) ──
class _BorrowerGridTile3Col extends StatelessWidget {
  final Borrower borrower;
  final NumberFormat fmt;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BorrowerGridTile3Col({
    required this.borrower,
    required this.fmt,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final b = borrower;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFF1F5F9),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AnimatedAvatar(name: b.fullName, size: 28),
                StatusDot(status: b.status),
              ],
            ),
            const SizedBox(height: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    color: AppTheme.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  b.loanReference,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            Text(
              '₱${fmt.format(b.amountBorrowed)}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: Color(0xFFC68A0E),
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
