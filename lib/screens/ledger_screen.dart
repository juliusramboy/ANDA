import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../models/payment.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => LedgerScreenState();
}

class LedgerScreenState extends State<LedgerScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  double totalCollected = 0;
  double thisMonth = 0;
  int fullyPaidCount = 0;
  List<Borrower> fullyPaid = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void refresh() {
    _load();
  }

  Future<void> _load() async {
    final tc = await db.getTotalCollected();
    final tm = await db.getThisMonthCollected();
    final fc = await db.getFullyPaidCount();
    final fp = await db.getFullyPaidBorrowers();
    setState(() {
      totalCollected = tc;
      thisMonth = tm;
      fullyPaidCount = fc;
      fullyPaid = fp;
      loading = false;
    });
  }

  String _completedDate(Borrower b) {
    try {
      final d = DateFormat('MM/dd/yyyy').parse(b.repaymentDate);
      return 'Completed ${DateFormat('MMM dd, yyyy').format(d)}';
    } catch (_) {
      return 'Completed ${b.repaymentDate}';
    }
  }

  double _growthPercent() {
    if (totalCollected == 0) return 0;
    return (thisMonth / totalCollected) * 100;
  }

  @override
  Widget build(BuildContext context) {
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
                      // ── Header ──
                      const Text('Ledger',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark)),
                      const SizedBox(height: 16),

                      // ── Hero card ──
                      NavyCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TOTAL COLLECTED',
                                style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 4),
                            Text(
                              '₱${fmt.format(totalCollected)}',
                              style: const TextStyle(
                                  color: AppTheme.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  '₱${fmt.format(thisMonth)}',
                                  style: const TextStyle(
                                      color: AppTheme.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Settled This Month',
                                    style: TextStyle(
                                        color: Colors.white60, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.yellow,
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                  child: Text(
                                    '+${_growthPercent().toStringAsFixed(0)}% GROWTH',
                                    style: const TextStyle(
                                        color: AppTheme.navy,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Fully Paid ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Fully Paid\nMemberships',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$fullyPaidCount',
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textDark),
                              ),
                              const Text('TOTAL',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.textGrey,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (fullyPaid.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Text('No fully paid borrowers yet.',
                                style: TextStyle(color: AppTheme.textGrey)),
                          ),
                        )
                      else
                        ...fullyPaid.map((b) => _LedgerRow(
                            borrower: b,
                            completedDate: _completedDate(b),
                            fmt: fmt)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _LedgerRow extends StatefulWidget {
  final Borrower borrower;
  final String completedDate;
  final NumberFormat fmt;

  const _LedgerRow({
    required this.borrower,
    required this.completedDate,
    required this.fmt,
  });

  @override
  State<_LedgerRow> createState() => _LedgerRowState();
}

class _LedgerRowState extends State<_LedgerRow> {
  bool _expanded = false;
  List<Payment> _payments = [];
  bool _loading = false;

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    try {
      final list = await DatabaseHelper.instance.getPaymentsByBorrower(widget.borrower.id!);
      if (mounted) {
        setState(() {
          _payments = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatPaymentDate(String dateStr) {
    try {
      final d = DateFormat('MM/dd/yyyy').parse(dateStr);
      return DateFormat('MMMM dd, yyyy').format(d);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
              if (_expanded && _payments.isEmpty) {
                _loadPayments();
              }
            },
            child: Row(
              children: [
                AnimatedAvatar(
                    name: widget.borrower.fullName,
                    size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.borrower.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(widget.completedDate,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textGrey)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₱${widget.fmt.format(widget.borrower.amountBorrowed)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    StatusBadge(label: 'FULLY PAID', color: AppTheme.green),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: AppTheme.textGrey,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Divider(color: AppTheme.lightGrey, height: 1),
                const SizedBox(height: 12),
                const Text(
                  'PAYMENT HISTORY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textGrey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_payments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No payments recorded.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textGrey),
                    ),
                  )
                else
                  Column(
                    children: _payments.map((p) {
                      final isInterest = p.paymentType == 'Interest';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.paymentType,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatPaymentDate(p.paymentDate),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textGrey,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '₱${widget.fmt.format(p.amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isInterest ? AppTheme.red : AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}


