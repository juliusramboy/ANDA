import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../database/database_helper.dart';
import '../models/borrower.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class AddLoanScreen extends StatefulWidget {
  final Borrower? existing; // non-null = edit mode
  const AddLoanScreen({super.key, this.existing});

  @override
  State<AddLoanScreen> createState() => _AddLoanScreenState();
}

class _AddLoanScreenState extends State<AddLoanScreen> {
  final db = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  final nameCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  final agreedAmountCtrl = TextEditingController();
  final dateCtrl = TextEditingController();
  final oneTimeInterestCtrl = TextEditingController();

  String interestRate = '5';
  String repaymentTerm = '1 Month';
  String loanRef = '';
  String issueDate = '';
  String? signaturePath;
  bool saving = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    issueDate = DateFormat('MMM d, yyyy').format(DateTime.now());

    if (isEdit) {
      final b = widget.existing!;
      loanRef = b.loanReference;
      nameCtrl.text = b.fullName;
      amountCtrl.text = b.amountBorrowed.toString();
      agreedAmountCtrl.text = b.agreedSetupAmount?.toString() ?? '';
      if (b.isOneTimeInterest) {
        interestRate = '1-Time';
        oneTimeInterestCtrl.text = b.interestRate.toString();
      } else {
        interestRate = b.interestRate.toInt().toString();
      }
      dateCtrl.text = b.repaymentDate;
      signaturePath = b.signatureImagePath;
      issueDate = b.issueDate;
      repaymentTerm = 'Custom'; // Default to custom on edit to preserve saved date
    } else {
      _genRef();
      _updateRepaymentDate();
    }
  }

  Future<void> _genRef() async {
    final ref = await db.generateLoanReference();
    setState(() => loanRef = ref);
  }

  DateTime _getRepaymentDateForMonths(DateTime baseDate, int monthsToAdd) {
    int year = baseDate.year;
    int month = baseDate.month + monthsToAdd;
    
    year += (month - 1) ~/ 12;
    month = (month - 1) % 12 + 1;
    
    int day = baseDate.day;
    int daysInMonth = DateTime(year, month + 1, 0).day;
    if (day > daysInMonth) {
      day = daysInMonth;
    }
    
    return DateTime(year, month, day);
  }

  void _updateRepaymentDate() {
    if (repaymentTerm == 'Custom') return;

    DateTime issue;
    try {
      issue = DateFormat('MMM d, yyyy').parse(issueDate);
    } catch (_) {
      issue = DateTime.now();
    }

    int months = 1;
    if (repaymentTerm == '2 Months') months = 2;
    if (repaymentTerm == '3 Months') months = 3;

    final repayment = _getRepaymentDateForMonths(issue, months);
    dateCtrl.text = DateFormat('MM/dd/yyyy').format(repayment);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    amountCtrl.dispose();
    agreedAmountCtrl.dispose();
    dateCtrl.dispose();
    oneTimeInterestCtrl.dispose();
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

  Future<void> _pickIssueDate() async {
    DateTime initial = DateTime.now();
    if (issueDate.isNotEmpty) {
      try {
        initial = DateFormat('MMM d, yyyy').parse(issueDate);
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        issueDate = DateFormat('MMM d, yyyy').format(picked);
        _updateRepaymentDate();
      });
    }
  }

  Future<void> _pickSignature() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img != null) setState(() => signaturePath = img.path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => saving = true);

    final agreedText = agreedAmountCtrl.text.trim();
    final double? agreedAmount =
        agreedText.isEmpty ? null : double.tryParse(agreedText);

    final isOneTime = interestRate == '1-Time';
    final double parsedInterestRate = isOneTime
        ? double.parse(oneTimeInterestCtrl.text.trim())
        : double.parse(interestRate);

    final borrower = Borrower(
      id: isEdit ? widget.existing!.id : null,
      loanReference: loanRef,
      fullName: nameCtrl.text.trim(),
      amountBorrowed: double.parse(amountCtrl.text),
      interestRate: parsedInterestRate,
      repaymentDate: dateCtrl.text,
      issueDate: issueDate,
      signatureImagePath: signaturePath,
      status: 'active',
      agreedSetupAmount: agreedAmount,
      isOneTimeInterest: isOneTime,
    );

    if (isEdit) {
      await db.updateBorrower(borrower);
    } else {
      await db.insertBorrower(borrower);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isEdit)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      padding: EdgeInsets.zero,
                    ),
                  Text(
                    isEdit ? 'Edit Loan' : 'Add New Loan',
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark),
                  ),
                  const Text(
                    "Enter the borrower's details and loan terms below.",
                    style: TextStyle(fontSize: 13, color: AppTheme.textGrey),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Auto fields ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('LOAN REFERENCE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textGrey,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                  loanRef.isEmpty ? '...' : loanRef,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.navy),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: _pickIssueDate,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('ISSUE DATE',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textGrey,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.calendar_today,
                                          size: 13, color: AppTheme.navy),
                                      const SizedBox(width: 4),
                                      Text(
                                        issueDate,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: AppTheme.navy),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Borrower name ──
                      VaultTextField(
                        label: 'BORROWER NAME',
                        hint: 'Full Legal Name',
                        controller: nameCtrl,
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // ── Amount ──
                      VaultTextField(
                        label: 'AMOUNT TO BORROW',
                        hint: '0.00',
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        prefix: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('₱',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null)
                            return 'Invalid amount';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Agreed Setup Amount (Optional) ──
                      VaultTextField(
                        label: 'AGREED SETUP AMOUNT (OPTIONAL)',
                        hint: '0.00',
                        controller: agreedAmountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        prefix: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('₱',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        validator: (v) {
                          if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                            return 'Invalid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Interest rate ──
                      const Text('INTEREST RATE',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textGrey,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['5', '10', '15', '20', '1-Time'].map((rate) {
                          final selected = interestRate == rate;
                          final label = rate == '1-Time' ? '1-Time Pay' : '$rate% Monthly';
                          return GestureDetector(
                            onTap: () => setState(() => interestRate = rate),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected ? AppTheme.yellow : AppTheme.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: selected ? AppTheme.yellow : AppTheme.lightGrey,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: selected ? AppTheme.navy : AppTheme.textGrey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (interestRate == '1-Time') ...[
                        const SizedBox(height: 16),
                        VaultTextField(
                          label: 'ONE-TIME INTEREST AMOUNT',
                          hint: '0.00',
                          controller: oneTimeInterestCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          prefix: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('₱',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (double.tryParse(v) == null)
                              return 'Invalid amount';
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),

                      // ── Repayment Term ──
                      const Text('REPAYMENT TERM',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textGrey,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['1 Month', '2 Months', '3 Months', 'Custom'].map((term) {
                          final selected = repaymentTerm == term;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                repaymentTerm = term;
                                _updateRepaymentDate();
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected ? AppTheme.yellow : AppTheme.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: selected ? AppTheme.yellow : AppTheme.lightGrey,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                term,
                                style: TextStyle(
                                  color: selected ? AppTheme.navy : AppTheme.textGrey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // ── Repayment date ──
                      VaultTextField(
                        label: 'REPAYMENT DATE',
                        hint: 'mm/dd/yyyy',
                        controller: dateCtrl,
                        readOnly: true,
                        onTap: () {
                          if (repaymentTerm != 'Custom') {
                            setState(() {
                              repaymentTerm = 'Custom';
                            });
                          }
                          _pickDate();
                        },
                        suffix: const Icon(Icons.calendar_today_outlined,
                            size: 18, color: AppTheme.textGrey),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),

                      // ── Signature ──
                      const Text('SIGNATURE AUTHENTICATION',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textGrey,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickSignature,
                        child: Container(
                          width: double.infinity,
                          height: 140,
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.lightGrey,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: signaturePath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.file(
                                    File(signaturePath!),
                                    fit: BoxFit.contain,
                                  ),
                                )
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit_outlined,
                                        color: AppTheme.navy, size: 32),
                                    SizedBox(height: 8),
                                    Text(
                                      'Upload picture of signature',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppTheme.textDark),
                                    ),
                                    SizedBox(height: 4),
                                    Text('PNG, JPG UP TO 5MB',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textGrey)),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Submit ──
                      saving
                          ? const Center(child: CircularProgressIndicator())
                          : YellowButton(
                              label: isEdit
                                  ? 'Update Loan'
                                  : 'Finalize Loan Agreement',
                              icon: Icons.shield_outlined,
                              onTap: _save,
                            ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
