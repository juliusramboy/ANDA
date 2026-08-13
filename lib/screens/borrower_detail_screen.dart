import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../models/payment.dart';
import '../models/interest_charge.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'payment_history_screen.dart';
import 'record_payment_modal.dart';
import '../services/auth_service.dart';

class BorrowerDetailScreen extends StatefulWidget {
  final int borrowerId;
  const BorrowerDetailScreen({super.key, required this.borrowerId});

  @override
  State<BorrowerDetailScreen> createState() => _BorrowerDetailScreenState();
}

class _BorrowerDetailScreenState extends State<BorrowerDetailScreen> {
  final db = DatabaseHelper.instance;
  final fmt = NumberFormat('#,##0.00');

  Borrower? borrower;
  List<Payment> recentPayments = [];
  List<Payment> allPayments = [];
  List<InterestCharge> interestCharges = [];
  double totalPaid = 0;
  double remainingPrincipal = 0;
  double remainingInterest = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await db.getBorrowerById(widget.borrowerId);
    if (b == null) {
      setState(() {
        borrower = null;
        loading = false;
      });
      return;
    }
    final payments = await db.getPaymentsByBorrower(widget.borrowerId);
    final total = await db.getTotalPaidByBorrower(widget.borrowerId);

    final remPrincipal = b.calculateRemainingPrincipal(payments);
    final maturityBalance = b.calculateMaturityBalance(payments);
    final remainingMaturity = max(0.0, maturityBalance - total);
    final remInterest = max(0.0, remainingMaturity - remPrincipal);
    final charges = b.calculateInterestCharges(payments);

    setState(() {
      borrower = b;
      allPayments = payments;
      recentPayments = payments.take(2).toList();
      interestCharges = charges;
      totalPaid = total;
      remainingPrincipal = remPrincipal;
      remainingInterest = remInterest;
      loading = false;
    });
  }

  Future<void> _updateSignature() async {
    if (borrower == null) return;
    final picker = ImagePicker();
    final hasSig = borrower!.signatureImagePath != null &&
        borrower!.signatureImagePath!.isNotEmpty;

    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: AppTheme.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasSig ? 'Update Signature' : 'Add Signature',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppTheme.navy),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.navy),
                title: const Text('Take Photo with Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              if (hasSig)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppTheme.red),
                  title: const Text('Remove Signature', style: TextStyle(color: AppTheme.red)),
                  onTap: () async {
                    Navigator.pop(ctx, null);
                    final updated = borrower!.copyWith(signatureImagePath: '');
                    await db.updateBorrower(updated);
                    _load();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Signature removed successfully'),
                          backgroundColor: AppTheme.navy,
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final img = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 400,
      imageQuality: 85,
    );

    if (img != null) {
      final bytes = await img.readAsBytes();
      final base64Str = base64Encode(bytes);
      final updated = borrower!.copyWith(signatureImagePath: base64Str);
      await db.updateBorrower(updated);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signature updated successfully!'),
            backgroundColor: AppTheme.green,
          ),
        );
      }
    }
  }

  void _showRecordPayment() async {
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _VerifyIdentityDialog(),
    );

    if (verified == true) {
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => RecordPaymentModal(borrower: borrower!),
      );
      _load();
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Borrower'),
        content: Text(
            'Are you sure you want to delete ${borrower!.fullName}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await db.deleteBorrower(widget.borrowerId);
              if (mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red, foregroundColor: AppTheme.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditPenaltyDialog(InterestCharge charge, String dateStr) {
    final controller = TextEditingController(text: charge.totalAmount.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cream,
        title: const Text(
          'Edit Penalty Amount',
          style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Anniversary: ${DateFormat('MMMM dd, yyyy').format(charge.date)}',
                style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
            const SizedBox(height: 16),
            const Text('PENALTY AMOUNT (PHP)',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newAmount = double.tryParse(controller.text.trim());
              if (newAmount == null || newAmount < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid amount.'), backgroundColor: AppTheme.red),
                );
                return;
              }
              Navigator.pop(ctx);
              
              final map = borrower!.getCustomPenaltyMap();
              map[dateStr] = newAmount;
              
              final updated = borrower!.copyWith(
                customPenaltyAmounts: jsonEncode(map),
              );
              
              await db.updateBorrower(updated);
              await db.updateBorrowerStatusIfNeeded(borrower!.id!);
              await _load();
              
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Penalty amount updated successfully!'), backgroundColor: AppTheme.green),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.navy, foregroundColor: AppTheme.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (borrower == null) {
      return const Scaffold(body: Center(child: Text('Not found')));
    }

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(borrower!.fullName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17)),
                        Row(
                          children: [
                            StatusDot(status: borrower!.status),
                            const SizedBox(width: 6),
                            Text(
                              borrower!.status == 'active'
                                  ? 'ACTIVE MEMBER'
                                  : borrower!.status.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textGrey,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'delete') _showDeleteDialog();
                      if (v == 'collect') {
                        final maturityBalance = borrower!.calculateMaturityBalance(allPayments);
                        final remainingBalance = max(0.0, maturityBalance - totalPaid);

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Collect Maturity Balance'),
                            content: Text(
                              'Are you sure you want to collect the remaining maturity balance of '
                              '₱${fmt.format(remainingBalance)} from ${borrower!.fullName}?\n\n'
                              'This will record a final maturity payment for the remaining balance '
                              'and set the status to fully paid.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.green,
                                  foregroundColor: AppTheme.white,
                                ),
                                child: const Text('Confirm'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          if (!context.mounted) return;
                          final verified = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const _VerifyIdentityDialog(),
                          );

                          if (verified == true) {
                            if (remainingBalance > 0) {
                              await db.insertPayment(Payment(
                                borrowerId: borrower!.id!,
                                amount: remainingBalance,
                                paymentType: 'Maturity Collection',
                                paymentDate: DateFormat('MM/dd/yyyy').format(DateTime.now()),
                                notes: 'Collected remaining maturity balance (Principal + Interest).',
                                status: 'paid',
                              ));
                            } else {
                              await db.updateBorrower(borrower!.copyWith(status: 'fully_paid'));
                            }
                            _load();

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Successfully collected ₱${fmt.format(remainingBalance)} from ${borrower!.fullName}.'),
                                  backgroundColor: AppTheme.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      if (borrower!.status != 'fully_paid')
                        const PopupMenuItem(
                          value: 'collect',
                          child: Text('Collect Maturity Balance'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: AppTheme.red)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Hero card ──
                    _FlippableHeroCard(
                      borrower: borrower!,
                      payments: allPayments,
                      remainingPrincipal: remainingPrincipal,
                      remainingInterest: remainingInterest,
                      fmt: fmt,
                    ),
                    const SizedBox(height: 24),

                    // ── Payment History ──
                    SectionHeader(
                      title: 'PAYMENT HISTORY',
                      actionLabel: 'VIEW ALL',
                      onAction: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PaymentHistoryScreen(borrower: borrower!),
                          ),
                        ).then((_) => _load());
                      },
                    ),
                    const SizedBox(height: 12),

                    if (recentPayments.isEmpty)
                      const Center(
                          child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No payments yet.',
                            style: TextStyle(color: AppTheme.textGrey)),
                      ))
                    else
                      ...recentPayments.map((p) => _PaymentRow(payment: p)),

                    const SizedBox(height: 24),

                    // ── Interest & Penalties ──
                    const SectionHeader(title: 'INTEREST & PENALTIES'),
                    const SizedBox(height: 12),

                    if (interestCharges.isEmpty)
                      const Center(
                          child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No interest/penalties accrued yet.',
                            style: TextStyle(color: AppTheme.textGrey)),
                      ))
                    else
                      ...interestCharges.map((charge) {
                        final isWaived = charge.isWaived;
                        final isUnpaid = !isWaived && charge.unpaidAmount > 0.001;
                        final isPartial = !isWaived && charge.paidAmount > 0.001 && isUnpaid;
                        
                        final statusLabel = isWaived
                            ? 'WAIVED'
                            : (isPartial
                                ? '₱${fmt.format(charge.unpaidAmount)} UNPAID'
                                : (isUnpaid ? 'UNPAID' : 'PAID'));
                        final statusColor = isWaived
                            ? AppTheme.textGrey
                            : (isPartial
                                ? AppTheme.yellow
                                : (isUnpaid ? AppTheme.red : AppTheme.green));

                        final chargeDateStr = DateFormat('MM/dd/yyyy').format(charge.date);
                        final isPenalty = charge.label.contains("Penalty");

                        Widget cardContent = Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.lightGrey,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isWaived ? Icons.close : Icons.info_outline,
                                  size: 18,
                                  color: AppTheme.textGrey,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      charge.label + (isWaived ? ' (Waived)' : ''),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        decoration: isWaived ? TextDecoration.lineThrough : null,
                                        color: isWaived ? AppTheme.textGrey : AppTheme.textDark,
                                      ),
                                    ),
                                    Text(DateFormat('MMMM dd, yyyy').format(charge.date),
                                        style: const TextStyle(
                                            fontSize: 11, color: AppTheme.textGrey)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₱${fmt.format(charge.totalAmount)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      decoration: isWaived ? TextDecoration.lineThrough : null,
                                      color: isWaived ? AppTheme.textGrey : AppTheme.textDark,
                                    ),
                                  ),
                                  StatusBadge(
                                    label: statusLabel,
                                    color: statusColor,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );

                        if (isPenalty) {
                          return Dismissible(
                            key: ValueKey('charge_${charge.date.millisecondsSinceEpoch}_${charge.label}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: isWaived ? AppTheme.green : AppTheme.red,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(
                                    isWaived ? Icons.restore : Icons.block,
                                    color: AppTheme.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isWaived ? 'Restore Penalty' : 'Waive Penalty',
                                    style: const TextStyle(
                                      color: AppTheme.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onDismissed: (direction) async {
                              final backupWaived = borrower!.waivedPenaltyDates;
                              final currentWaivedList = borrower!.waivedPenaltyDates
                                  ?.split(',')
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList() ?? [];

                              if (isWaived) {
                                currentWaivedList.remove(chargeDateStr);
                              } else {
                                if (!currentWaivedList.contains(chargeDateStr)) {
                                  currentWaivedList.add(chargeDateStr);
                                }
                              }

                              final newWaivedStr = currentWaivedList.join(',');
                              final updatedBorrower = borrower!.copyWith(waivedPenaltyDates: newWaivedStr);

                              await db.updateBorrower(updatedBorrower);
                              await db.updateBorrowerStatusIfNeeded(borrower!.id!);
                              await _load();

                              if (!mounted) return;

                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isWaived
                                      ? 'Restored penalty for ${DateFormat('MMMM dd, yyyy').format(charge.date)}.'
                                      : 'Waived penalty for ${DateFormat('MMMM dd, yyyy').format(charge.date)}.'),
                                  behavior: SnackBarBehavior.floating,
                                  action: SnackBarAction(
                                    label: 'UNDO',
                                    textColor: AppTheme.yellow,
                                    onPressed: () async {
                                      final restoredBorrower = borrower!.copyWith(waivedPenaltyDates: backupWaived);
                                      await db.updateBorrower(restoredBorrower);
                                      await db.updateBorrowerStatusIfNeeded(restoredBorrower.id!);
                                      _load();
                                    },
                                  ),
                                ),
                              );
                            },
                            child: GestureDetector(
                              onLongPress: () => _showEditPenaltyDialog(charge, chargeDateStr),
                              child: cardContent,
                            ),
                          );
                        }

                        return cardContent;
                      }),

                    const SizedBox(height: 24),

                    // ── Membership Contract ──
                    const SectionHeader(title: 'MEMBERSHIP CONTRACT'),
                    const SizedBox(height: 12),

                    Builder(builder: (context) {
                      final hasSig = borrower!.signatureImagePath != null &&
                          borrower!.signatureImagePath!.trim().isNotEmpty;
                      return Container(
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            onTap: () =>
                                PdfService.viewContract(context, borrower!),
                            onLongPress: _updateSignature,
                            leading: const Icon(Icons.description_outlined,
                                color: AppTheme.navy),
                            title: Text(
                              '${borrower!.fullName.replaceAll(' ', '_')}_Contract.pdf',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Text(
                              hasSig
                                  ? 'Signed ${borrower!.issueDate} (Hold to edit signature)'
                                  : 'No signature attached (Hold to add signature)',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: hasSig
                                      ? AppTheme.textGrey
                                      : AppTheme.orange),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 20, color: AppTheme.navy),
                                  tooltip: 'Edit Signature',
                                  onPressed: _updateSignature,
                                ),
                                GestureDetector(
                                  onTap: () => PdfService.downloadContract(
                                      context, borrower!),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.yellow,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.download,
                                        size: 16, color: AppTheme.navy),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 28),

                    // ── Actions ──
                    YellowButton(
                      label: 'Download all payment history',
                      icon: Icons.download,
                      onTap: () => PdfService.downloadPaymentHistory(
                          context, borrower!, allPayments),
                    ),
                    const SizedBox(height: 12),
                    if (borrower!.status != 'fully_paid') ...[
                      OutlineButton2(
                        label: 'Record Payment',
                        icon: Icons.edit_outlined,
                        onTap: _showRecordPayment,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Payment payment;
  const _PaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final isCredit = payment.status == 'credited';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.lightGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.receipt_outlined,
                size: 18, color: AppTheme.textGrey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.paymentType,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                Text(payment.paymentDate,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textGrey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '-' : ''}₱${fmt.format(payment.amount)}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              StatusBadge(
                label: payment.status.toUpperCase(),
                color: isCredit ? AppTheme.blue : AppTheme.green,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerifyIdentityDialog extends StatefulWidget {
  const _VerifyIdentityDialog();

  @override
  State<_VerifyIdentityDialog> createState() => _VerifyIdentityDialogState();
}

class _VerifyIdentityDialogState extends State<_VerifyIdentityDialog> {
  final _passwordCtrl = TextEditingController();
  String _errorText = '';
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    _initBiometrics();
  }

  Future<void> _initBiometrics() async {
    final canUse = await AuthService.canAuthenticate();
    if (mounted) {
      setState(() {
        _canUseBiometrics = canUse;
      });
      if (canUse) {
        _authenticateBiometrically();
      }
    }
  }

  Future<void> _authenticateBiometrically() async {
    final authenticated = await AuthService.authenticate(
      reason: 'Authenticate to approve transaction',
    );
    if (authenticated && mounted) {
      Navigator.pop(context, true);
    }
  }

  void _confirm() {
    if (_passwordCtrl.text == 'julius') {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _errorText = 'Invalid password';
      });
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cream,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SECURITY CHECK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.navy,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Verify Identity',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.navy,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppTheme.textDark),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Password Field
            const Text(
              'Enter Password',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textGrey,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              style: const TextStyle(color: AppTheme.textDark),
              decoration: InputDecoration(
                suffixIcon: _canUseBiometrics
                    ? IconButton(
                        icon: const Icon(Icons.fingerprint, color: AppTheme.navy),
                        onPressed: _authenticateBiometrically,
                      )
                    : const Icon(Icons.lock_outline, color: AppTheme.textGrey),
                filled: true,
                fillColor: AppTheme.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.lightGrey),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.lightGrey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.navy, width: 1.5),
                ),
                errorText: _errorText.isEmpty ? null : _errorText,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Please enter your administrator password to proceed with recording this payment.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textGrey,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.navy,
                      side: const BorderSide(color: AppTheme.navy),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.yellow,
                      foregroundColor: AppTheme.navy,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FlippableHeroCard extends StatefulWidget {
  final Borrower borrower;
  final List<Payment> payments;
  final double remainingPrincipal;
  final double remainingInterest;
  final NumberFormat fmt;

  const _FlippableHeroCard({
    required this.borrower,
    required this.payments,
    required this.remainingPrincipal,
    required this.remainingInterest,
    required this.fmt,
  });

  @override
  State<_FlippableHeroCard> createState() => _FlippableHeroCardState();
}

class _FlippableHeroCardState extends State<_FlippableHeroCard>
    with TickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  Timer? _shakeTimer;

  bool _isFront = true;

  @override
  void initState() {
    super.initState();

    // Flip Animation
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    // Shake Hint Animation
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );

    // Run the shake animation once the card mounts to hint at interactive flipping
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _shakeController.forward(from: 0);
      }
    });

    // Run wiggle animation periodically every 6 seconds if showing the front
    _shakeTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (mounted && _isFront) {
        _shakeController.forward(from: 0);
      }
    });
  }

  void _toggleFlip() {
    if (_isFront) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
    setState(() {
      _isFront = !_isFront;
    });
  }

  @override
  void dispose() {
    _flipController.dispose();
    _shakeController.dispose();
    _shakeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final interestAmount = widget.borrower.calculateTotalInterestAndPenalties(widget.payments);
    final maturityBalance = widget.borrower.calculateMaturityBalance(widget.payments);

    return GestureDetector(
      onDoubleTap: _toggleFlip,
      child: AnimatedBuilder(
        animation: Listenable.merge([_flipAnimation, _shakeAnimation]),
        builder: (context, child) {
          double flipAngle = _flipAnimation.value * pi;

          double shakeAngle = 0.0;
          if (_shakeController.isAnimating) {
            shakeAngle = sin(_shakeAnimation.value * 3 * pi) * 0.08;
          }

          double totalAngle = flipAngle + shakeAngle;
          final isBack = (flipAngle % (2 * pi)) > (pi / 2) &&
              (flipAngle % (2 * pi)) < (3 * pi / 2);

          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective
              ..rotateY(totalAngle),
            alignment: Alignment.center,
            child: isBack
                ? Transform(
                    transform: Matrix4.identity()..rotateY(pi),
                    alignment: Alignment.center,
                    child: _buildBackCard(interestAmount, maturityBalance),
                  )
                : _buildFrontCard(),
          );
        },
      ),
    );
  }

  Widget _buildFrontCard() {
    final showInterest = widget.remainingPrincipal <= 0;
    return NavyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                showInterest ? 'REMAINING INTEREST' : 'REMAINING PRINCIPAL',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  showInterest ? Icons.stars : Icons.account_balance_wallet_outlined,
                  color: showInterest ? AppTheme.yellow : AppTheme.white,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '₱${widget.fmt.format(showInterest ? widget.remainingInterest : widget.remainingPrincipal)}',
            style: TextStyle(
              color: showInterest ? AppTheme.yellow : AppTheme.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NEXT PAYMENT DUE',
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            letterSpacing: 0.5)),
                    Text(widget.borrower.repaymentDate,
                        style: const TextStyle(
                            color: AppTheme.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BILLING CYCLE',
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            letterSpacing: 0.5)),
                    Text(widget.borrower.billingCycle,
                        style: const TextStyle(
                            color: AppTheme.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackCard(double interestAmount, double maturityBalance) {
    return NavyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('MATURITY BALANCE',
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      letterSpacing: 0.5)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                    Icons.stars,
                    color: AppTheme.yellow,
                    size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '₱${widget.fmt.format(maturityBalance)}',
            style: const TextStyle(
              color: AppTheme.yellow,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MATURITY DATE',
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            letterSpacing: 0.5)),
                    Text(widget.borrower.repaymentDate,
                        style: const TextStyle(
                            color: AppTheme.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Amount Intrest',
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            letterSpacing: 0.5)),
                    Text('₱${widget.fmt.format(interestAmount)}',
                        style: const TextStyle(
                            color: AppTheme.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
