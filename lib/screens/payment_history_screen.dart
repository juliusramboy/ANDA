import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../models/payment.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class PaymentHistoryScreen extends StatefulWidget {
  final Borrower borrower;
  const PaymentHistoryScreen({super.key, required this.borrower});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  List<Payment> payments = [];
  double totalPaid = 0;
  int payCount = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await db.getPaymentsByBorrower(widget.borrower.id!);
    final t = await db.getTotalPaidByBorrower(widget.borrower.id!);
    final c = await db.getPaymentCountByBorrower(widget.borrower.id!);
    setState(() {
      payments = p;
      totalPaid = t;
      payCount = c;
      loading = false;
    });
  }

  void _showDeletePayment(Payment payment) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Payment'),
        content: const Text('Remove this payment record?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await db.deletePayment(payment.id!);
              Navigator.pop(context);
              _load();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red, foregroundColor: AppTheme.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── App bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Payment History',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 17)),
                      Text(widget.borrower.fullName,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textGrey)),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        // ── Hero ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: NavyCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('LIFETIME PAID',
                                    style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                        letterSpacing: 0.5)),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₱${fmt.format(totalPaid)}',
                                      style: const TextStyle(
                                          color: AppTheme.white,
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.yellow,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle,
                                          size: 16, color: AppTheme.navy),
                                      const SizedBox(width: 6),
                                      const Text('Successful Payments',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: AppTheme.navy)),
                                      const SizedBox(width: 8),
                                      Text('$payCount',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                              color: AppTheme.navy)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Filter bar ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('TRANSACTION HISTORY',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textGrey,
                                      letterSpacing: 0.5)),
                              GestureDetector(
                                onTap: () {},
                                child: const Text('FILTER',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.navy)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ── List ──
                        Expanded(
                          child: payments.isEmpty
                              ? const Center(
                                  child: Text('No payments yet.',
                                      style:
                                          TextStyle(color: AppTheme.textGrey)))
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  itemCount: payments.length,
                                  itemBuilder: (ctx, i) {
                                    final p = payments[i];
                                    final isCredit = p.status == 'credited';
                                    return Dismissible(
                                      key: Key('payment_${p.id}'),
                                      direction: DismissDirection.endToStart,
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding:
                                            const EdgeInsets.only(right: 20),
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        decoration: BoxDecoration(
                                          color: AppTheme.red.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: const Icon(Icons.delete,
                                            color: AppTheme.red),
                                      ),
                                      confirmDismiss: (_) async {
                                        _showDeletePayment(p);
                                        return false;
                                      },
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: AppTheme.white,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: AppTheme.lightGrey,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                isCredit
                                                    ? Icons.star_outline
                                                    : Icons.receipt_outlined,
                                                size: 18,
                                                color: AppTheme.textGrey,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(p.paymentType,
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13)),
                                                  Text(p.paymentDate,
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppTheme
                                                              .textGrey)),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '${isCredit ? '-' : ''}₱${fmt.format(p.amount)}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14),
                                                ),
                                                StatusBadge(
                                                  label: p.status.toUpperCase(),
                                                  color: isCredit
                                                      ? AppTheme.blue
                                                      : AppTheme.green,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),

                        // ── Download ──
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: YellowButton(
                            label: 'Download All Receipts',
                            icon: Icons.download,
                            onTap: () => PdfService.downloadPaymentHistory(
                                context, widget.borrower, payments),
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
