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
import 'record_payment_modal.dart';
import 'add_loan_screen.dart';
import '../services/auth_service.dart';
import '../services/supabase_sync_service.dart';

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
  List<Payment> allPayments = [];
  List<InterestCharge> interestCharges = [];
  double totalPaid = 0;
  double remainingPrincipal = 0;
  double remainingInterest = 0;
  bool loading = true;
  bool _isCardExpanded = true;

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

    if (mounted) {
      setState(() {
        borrower = b;
        allPayments = payments;
        interestCharges = charges;
        totalPaid = total;
        remainingPrincipal = remPrincipal;
        remainingInterest = remInterest;
        loading = false;
      });
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
            'Are you sure you want to permanently delete ${borrower?.fullName}? This will also delete all associated payment records.'),
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
                SupabaseSyncService.instance.syncWithFeedback(
                  context,
                  actionName: 'Borrower deleted',
                );
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
                      SupabaseSyncService.instance.syncWithFeedback(
                        context,
                        actionName: 'Signature removed',
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
        SupabaseSyncService.instance.syncWithFeedback(
          context,
          actionName: 'Signature',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: AppTheme.cream,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (borrower == null) {
      return Scaffold(
        backgroundColor: AppTheme.cream,
        appBar: AppBar(backgroundColor: AppTheme.cream),
        body: const Center(child: Text('Borrower not found')),
      );
    }

    final b = borrower!;

    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Bar: Back Button & Header ──
              if (Navigator.canPop(context))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3EFEA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 16,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ),

              // ── Header: Borrower Name, Balance & More Menu Button ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.fullName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '₱${fmt.format(b.amountBorrowed)}',
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── More ⚙ Button & Popup Menu ──
                  PopupMenuButton<String>(
                    elevation: 12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Colors.white,
                    surfaceTintColor: Colors.white,
                    offset: const Offset(0, 48),
                    onSelected: (value) async {
                      if (value == 'record') {
                        _showRecordPayment();
                      } else if (value == 'export_contract') {
                        PdfService.viewContract(context, b);
                      } else if (value == 'export_history') {
                        PdfService.viewPaymentHistory(context, b, allPayments);
                      } else if (value == 'edit') {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddLoanScreen(existing: b),
                          ),
                        );
                        _load();
                      } else if (value == 'signature') {
                        _updateSignature();
                      } else if (value == 'delete') {
                        _showDeleteDialog();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'record',
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFC68A0E), size: 20),
                            SizedBox(width: 12),
                            Text('Record Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'export_contract',
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined, color: Color(0xFFC68A0E), size: 20),
                            SizedBox(width: 12),
                            Text('Export Contract', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'export_history',
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long_outlined, color: Color(0xFFC68A0E), size: 20),
                            SizedBox(width: 12),
                            Text('Export Payment History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, color: Color(0xFFC68A0E), size: 20),
                            SizedBox(width: 12),
                            Text('Edit Agreement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(height: 1),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: AppTheme.red, size: 20),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.red)),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'More',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(
                            Icons.settings_outlined,
                            size: 16,
                            color: AppTheme.textDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Collapsible Principal Loan Info Card (Cream Card) ──
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F3EB),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.03),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _isCardExpanded = !_isCardExpanded;
                        });
                      },
                      child: Row(
                        children: [
                          // Money Icon Box
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE6D8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.payments_outlined,
                              color: Color(0xFFC68A0E),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Principal',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFC68A0E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  b.status == 'active' ? 'Active Borrower' : b.status.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₱${fmt.format(remainingPrincipal)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFC68A0E),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _isCardExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: const Color(0xFFC68A0E),
                            size: 20,
                          ),
                        ],
                      ),
                    ),

                    // Expandable Details
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 250),
                      crossFadeState: _isCardExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [
                          const SizedBox(height: 14),
                          const Divider(height: 1, color: Colors.black12),
                          const SizedBox(height: 14),
                          _buildDetailRow('Billing Cycle', b.billingCycle),
                          const SizedBox(height: 10),
                          _buildDetailRow('Next Payment Due', b.repaymentDate),
                          const SizedBox(height: 10),
                          _buildDetailRow('Issue Date', b.issueDate),
                          const SizedBox(height: 10),
                          _buildDetailRow(
                            'Interest Rate',
                            '${b.interestRate}% ${b.isOneTimeInterest ? 'One-time' : b.billingCycle.toUpperCase()}',
                          ),
                          if (b.agreedSetupAmount != null) ...[
                            const SizedBox(height: 10),
                            _buildDetailRow('Agreed Setup Amount', '₱${fmt.format(b.agreedSetupAmount!)}'),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 20),

              // ── HISTORY Header ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'HISTORY',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF475569),
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    'Total P${fmt.format(totalPaid)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E1E24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Payments History List ──
              if (allPayments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No payments recorded yet.',
                      style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: allPayments.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 28,
                    color: Colors.black12,
                  ),
                  itemBuilder: (context, index) {
                    final p = allPayments[index];
                    return _buildPaymentHistoryRow(p);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentHistoryRow(Payment p) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.paymentType,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              p.paymentDate,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₱${fmt.format(p.amount)}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Color(0xFFC68A0E),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                p.status.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Verify Identity Modal Dialog ──
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
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
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
