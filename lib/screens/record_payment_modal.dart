import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../models/payment.dart';
import '../models/interest_charge.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/supabase_sync_service.dart';

class RecordPaymentModal extends StatefulWidget {
  final Borrower borrower;
  const RecordPaymentModal({super.key, required this.borrower});

  @override
  State<RecordPaymentModal> createState() => _RecordPaymentModalState();
}

class _RecordPaymentModalState extends State<RecordPaymentModal> {
  final db = DatabaseHelper.instance;
  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final dateCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String paymentType = 'Loan Principal';
  bool saving = false;
  double _unpaidInterest = 0.0;
  bool _loadingPayments = true;
  List<InterestCharge> _allCharges = [];
  List<InterestCharge> _unpaidPenalties = [];
  InterestCharge? _selectedPenalty;

  @override
  void initState() {
    super.initState();
    dateCtrl.text = DateFormat('MM/dd/yyyy').format(DateTime.now());
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    final list = await db.getPaymentsByBorrower(widget.borrower.id!);
    final charges = widget.borrower.calculateInterestCharges(list);
    final unpaidPens = charges.where((c) => c.label.contains("Penalty") && c.unpaidAmount > 0.001).toList();

    if (mounted) {
      setState(() {
        _unpaidInterest = widget.borrower.calculateTotalUnpaidInterest(list);
        _allCharges = charges;
        _unpaidPenalties = unpaidPens;
        _loadingPayments = false;
      });
    }
  }

  double _getInitialInterestUnpaid() {
    try {
      final initCharge = _allCharges.firstWhere((c) => c.label == "Initial Interest");
      return initCharge.unpaidAmount;
    } catch (_) {
      return 0.0;
    }
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    notesCtrl.dispose();
    dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    DateTime initial = DateTime.now();
    if (dateCtrl.text.isNotEmpty) {
      try {
        initial = DateFormat('MM/dd/yyyy').parse(dateCtrl.text);
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      dateCtrl.text = DateFormat('MM/dd/yyyy').format(picked);
    }
  }

  Future<bool> _verifySecurityPin() async {
    final settings = await SupabaseSyncService.instance.loadProfileSettings();
    final savedPin = settings['paymentPin'] ?? '1234';

    if (!mounted) return false;

    final pinCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Color(0xFFC68A0E), size: 22),
            SizedBox(width: 8),
            Text(
              'Enter Payment PIN',
              style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please enter your 4-digit security PIN to authorize and record this payment (Default: 1234):',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pinCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: '••••',
                counterText: '',
                filled: true,
                fillColor: const Color(0xFFF6F4EE),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              if (pinCtrl.text == savedPin) {
                Navigator.pop(ctx, true);
              } else {
                VaultToast.showError(
                  context,
                  'Incorrect PIN! Default is "1234". Change it in Profile.',
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC68A0E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final String? actualNotes;
    if (paymentType == 'Penalty') {
      if (_selectedPenalty == null) {
        VaultToast.showError(
          context,
          'Please select a penalty month to pay.',
        );
        return;
      }
      final dateStr = DateFormat('MM/dd/yyyy').format(_selectedPenalty!.date);
      actualNotes = 'Penalty: $dateStr';
    } else {
      actualNotes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
    }

    // Require PIN authorization
    final authorized = await _verifySecurityPin();
    if (!authorized) return;

    setState(() => saving = true);

    final payment = Payment(
      borrowerId: widget.borrower.id!,
      amount: double.parse(amountCtrl.text),
      paymentType: paymentType == 'Penalty' ? 'Late Fee' : paymentType,
      paymentDate: dateCtrl.text,
      notes: actualNotes,
      status: 'paid',
    );

    await db.insertPayment(payment);
    if (mounted) {
      Navigator.pop(context);
      SupabaseSyncService.instance.syncWithFeedback(
        context,
        actionName: 'Payment',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('RECORD PAYMENT FOR',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textGrey,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                        Text(widget.borrower.fullName,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark)),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (!_loadingPayments && _unpaidInterest > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppTheme.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Note: This member still has unpaid interest of ₱${NumberFormat('#,##0.00').format(_unpaidInterest)}.',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.red,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Amount ──
                VaultTextField(
                  label: 'AMOUNT PAID',
                  hint: '0.00',
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  prefix: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('₱',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark)),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Invalid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                const Text('Enter the total amount received from the member.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                const SizedBox(height: 16),

                // ── Payment type ──
                const Text('PAYMENT TYPE',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textGrey,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    children: ['Interest', 'Loan Principal', 'Penalty'].map((type) {
                      final selected = paymentType == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              paymentType = type;
                              if (type == 'Penalty' && _unpaidPenalties.isNotEmpty) {
                                _selectedPenalty = _unpaidPenalties.first;
                                amountCtrl.text = _selectedPenalty!.unpaidAmount.toStringAsFixed(2);
                              } else if (type == 'Interest') {
                                final initialUnpaid = _getInitialInterestUnpaid();
                                amountCtrl.text = initialUnpaid > 0 ? initialUnpaid.toStringAsFixed(2) : '';
                              } else {
                                amountCtrl.clear();
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color:
                                  selected ? AppTheme.navy : Colors.transparent,
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Text(
                              type,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    selected ? AppTheme.white : AppTheme.textGrey,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                if (paymentType == 'Penalty') ...[
                  const Text(
                    'LATE PENALTIES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textGrey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_unpaidPenalties.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'No unpaid penalties accrued.',
                        style: TextStyle(fontSize: 13, color: AppTheme.textGrey, fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    ..._unpaidPenalties.map((pen) {
                      final isSelected = _selectedPenalty == pen;
                      final penMonthStr = DateFormat('MMMM yyyy').format(pen.date);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedPenalty = pen;
                            amountCtrl.text = pen.unpaidAmount.toStringAsFixed(2);
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppTheme.navy : AppTheme.lightGrey,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: isSelected ? AppTheme.navy : AppTheme.textGrey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  penMonthStr,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ),
                              Text(
                                '₱${NumberFormat('#,##0.00').format(pen.unpaidAmount)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                ],

                // ── Date ──
                VaultTextField(
                  label: 'PAYMENT DATE',
                  controller: dateCtrl,
                  readOnly: true,
                  onTap: _pickDate,
                  suffix: const Icon(Icons.calendar_today_outlined,
                      size: 18, color: AppTheme.textGrey),
                ),
                const SizedBox(height: 16),

                if (paymentType != 'Penalty') ...[
                  // ── Notes ──
                  VaultTextField(
                    label: 'NOTES (OPTIONAL)',
                    hint: 'Add a short description...',
                    controller: notesCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Submit ──
                saving
                    ? const Center(child: CircularProgressIndicator())
                    : YellowButton(
                        label: 'Record Payment',
                        icon: Icons.receipt_long,
                        onTap: _save,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
