import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';
import '../services/supabase_sync_service.dart';

class LogNewExpenseModal extends StatefulWidget {
  final VoidCallback? onExpenseLogged;
  const LogNewExpenseModal({super.key, this.onExpenseLogged});

  @override
  State<LogNewExpenseModal> createState() => _LogNewExpenseModalState();
}

class _LogNewExpenseModalState extends State<LogNewExpenseModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _type = 'expense'; // Always expense type
  String _category = 'Investment';
  DateTime _selectedDate = DateTime.now();
  bool _isUrgent = false;
  bool _isPending = false;

  final List<String> _categories = [
    'Investment',
    'Essential',
    'Luho'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.navy,
              onPrimary: AppTheme.white,
              onSurface: AppTheme.textDark,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.navy,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final amountText = _amountCtrl.text.replaceAll(',', '').trim();
    final amount = double.tryParse(amountText) ?? 0.0;
    final notes = _notesCtrl.text.trim();
    final dateStr = DateFormat('MM/dd/yyyy').format(_selectedDate);

    final expense = Expense(
      name: name,
      amount: amount,
      category: _category,
      date: dateStr,
      notes: notes.isNotEmpty ? notes : null,
      type: _type,
      status: _isPending ? 'pending' : 'completed',
      isUrgent: _isUrgent,
    );

    await DatabaseHelper.instance.insertExpense(expense);

    if (mounted) {
      Navigator.pop(context);
      if (widget.onExpenseLogged != null) {
        widget.onExpenseLogged!();
      }
      SupabaseSyncService.instance.syncWithFeedback(
        context,
        actionName: 'Expense',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayDate = DateFormat('MM/dd/yyyy').format(_selectedDate);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top handle/close ──
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Log New Expense',
                    style: TextStyle(
                      color: AppTheme.navy,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppTheme.textGrey, size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              const SizedBox(height: 12),

              // EXPENSE NAME
              const Text(
                'TRANSACTION NAME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textGrey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EFEB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _nameCtrl,
                  validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a name' : null,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textDark,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Office Rent or Client Retainer',
                    hintStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // AMOUNT & CATEGORY Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Amount
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AMOUNT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textGrey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4EFEB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextFormField(
                            controller: _amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'Required';
                              final doubleAmount = double.tryParse(val.replaceAll(',', ''));
                              if (doubleAmount == null || doubleAmount <= 0) return 'Invalid';
                              return null;
                            },
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textDark,
                            ),
                            decoration: const InputDecoration(
                              prefixIcon: Padding(
                                padding: EdgeInsets.only(left: 16, right: 8, top: 12),
                                child: Text(
                                  '₱',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ),
                              prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                              hintText: '0.00',
                              hintStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Category
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CATEGORY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textGrey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4EFEB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _category,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textGrey),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textDark,
                              ),
                              dropdownColor: const Color(0xFFF4EFEB),
                              borderRadius: BorderRadius.circular(12),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _category = val);
                                }
                              },
                              items: _categories.map((c) {
                                return DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // DATE
              const Text(
                'DATE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textGrey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4EFEB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        displayDate,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const Icon(Icons.calendar_today, color: AppTheme.textDark, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // NOTES (OPTIONAL)
              const Text(
                'NOTES (OPTIONAL)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textGrey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EFEB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textDark,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Add details...',
                    hintStyle: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 12),

              // LOG TRANSACTION BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.yellow,
                    foregroundColor: AppTheme.navy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                  ),
                  child: const Text(
                    'LOG EXPENSE',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
