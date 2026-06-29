import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'interest_charge.dart';
import 'payment.dart';

class Borrower {
  final int? id;
  final String loanReference;
  final String fullName;
  final double amountBorrowed;
  final double interestRate;
  final String repaymentDate;
  final String issueDate;
  final String? signatureImagePath;
  final String status; // 'active', 'fully_paid', 'overdue'
  final String billingCycle; // 'Monthly', 'Quarterly', etc.
  final double? agreedSetupAmount;
  final String? dismissedWiggleDate;
  final bool isOneTimeInterest;
  final String? waivedPenaltyDates;
  final String? customPenaltyAmounts;

  Borrower({
    this.id,
    required this.loanReference,
    required this.fullName,
    required this.amountBorrowed,
    required this.interestRate,
    required this.repaymentDate,
    required this.issueDate,
    this.signatureImagePath,
    this.status = 'active',
    this.billingCycle = 'Monthly',
    this.agreedSetupAmount,
    this.dismissedWiggleDate,
    this.isOneTimeInterest = false,
    this.waivedPenaltyDates,
    this.customPenaltyAmounts,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'loanReference': loanReference,
        'fullName': fullName,
        'amountBorrowed': amountBorrowed,
        'interestRate': interestRate,
        'repaymentDate': repaymentDate,
        'issueDate': issueDate,
        'signatureImagePath': signatureImagePath,
        'status': status,
        'billingCycle': billingCycle,
        'agreedSetupAmount': agreedSetupAmount,
        'dismissedWiggleDate': dismissedWiggleDate,
        'isOneTimeInterest': isOneTimeInterest ? 1 : 0,
        'waivedPenaltyDates': waivedPenaltyDates,
        'customPenaltyAmounts': customPenaltyAmounts,
      };

  factory Borrower.fromMap(Map<String, dynamic> map) => Borrower(
        id: map['id'],
        loanReference: map['loanReference'],
        fullName: map['fullName'],
        amountBorrowed: map['amountBorrowed'],
        interestRate: map['interestRate'],
        repaymentDate: map['repaymentDate'],
        issueDate: map['issueDate'],
        signatureImagePath: map['signatureImagePath'],
        status: map['status'] ?? 'active',
        billingCycle: map['billingCycle'] ?? 'Monthly',
        agreedSetupAmount: map['agreedSetupAmount'] != null
            ? (map['agreedSetupAmount'] as num).toDouble()
            : null,
        dismissedWiggleDate: map['dismissedWiggleDate'],
        isOneTimeInterest: (map['isOneTimeInterest'] ?? 0) == 1,
        waivedPenaltyDates: map['waivedPenaltyDates'],
        customPenaltyAmounts: map['customPenaltyAmounts'],
      );

  Borrower copyWith({
    int? id,
    String? loanReference,
    String? fullName,
    double? amountBorrowed,
    double? interestRate,
    String? repaymentDate,
    String? issueDate,
    String? signatureImagePath,
    String? status,
    String? billingCycle,
    double? agreedSetupAmount,
    String? dismissedWiggleDate,
    bool? isOneTimeInterest,
    String? waivedPenaltyDates,
    String? customPenaltyAmounts,
  }) =>
      Borrower(
        id: id ?? this.id,
        loanReference: loanReference ?? this.loanReference,
        fullName: fullName ?? this.fullName,
        amountBorrowed: amountBorrowed ?? this.amountBorrowed,
        interestRate: interestRate ?? this.interestRate,
        repaymentDate: repaymentDate ?? this.repaymentDate,
        issueDate: issueDate ?? this.issueDate,
        signatureImagePath: signatureImagePath ?? this.signatureImagePath,
        status: status ?? this.status,
        billingCycle: billingCycle ?? this.billingCycle,
        agreedSetupAmount: agreedSetupAmount ?? this.agreedSetupAmount,
        dismissedWiggleDate: dismissedWiggleDate ?? this.dismissedWiggleDate,
        isOneTimeInterest: isOneTimeInterest ?? this.isOneTimeInterest,
        waivedPenaltyDates: waivedPenaltyDates ?? this.waivedPenaltyDates,
        customPenaltyAmounts: customPenaltyAmounts ?? this.customPenaltyAmounts,
      );

  Map<String, double> getCustomPenaltyMap() {
    if (customPenaltyAmounts == null || customPenaltyAmounts!.isEmpty) {
      return {};
    }
    try {
      final Map<String, dynamic> decoded = jsonDecode(customPenaltyAmounts!);
      return decoded.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  DateTime _getAnniversaryDate(DateTime baseDate, int monthsToAdd) {
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

  bool _isSameDay(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  DateTime? _parseDateSafe(String dateStr) {
    dateStr = dateStr.trim();
    dateStr = dateStr.replaceAll(RegExp(r'\s+'), ' ');

    final List<String> formats;
    if (RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}').hasMatch(dateStr)) {
      formats = [
        'yyyy-MM-dd',
        'yyyy/MM/dd',
      ];
    } else {
      formats = [
        'MMM d, yyyy',
        'MMMM d, yyyy',
        'MMM d yyyy',
        'MMMM d yyyy',
        'MM/dd/yyyy',
        'MM-dd-yyyy',
      ];
    }

    for (final fmt in formats) {
      try {
        return DateFormat(fmt, 'en_US').parse(dateStr);
      } catch (_) {}
      try {
        return DateFormat(fmt).parse(dateStr);
      } catch (_) {}
    }

    final direct = DateTime.tryParse(dateStr);
    if (direct != null) return direct;

    return null;
  }

  List<InterestCharge> calculateInterestCharges(List<Payment> payments, {DateTime? evaluationDate}) {
    final evalDate = evaluationDate ?? DateTime.now();
    
    if (isOneTimeInterest) {
      return [];
    }

    final repayment = _parseDateSafe(repaymentDate);
    if (repayment == null) {
      return [];
    }

    final waivedSet = waivedPenaltyDates
            ?.split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet() ??
        {};

    // Sum up payments of type 'Interest' or 'Maturity Collection' that are paid.
    final interestPaid = payments
        .where((p) => (p.paymentType == 'Interest' || p.paymentType == 'Maturity Collection') && p.status == 'paid')
        .fold<double>(0.0, (sum, p) => sum + p.amount);

    final issue = _parseDateSafe(issueDate) ?? repayment.subtract(const Duration(days: 30));

    int termMonths = (repayment.year - issue.year) * 12 + (repayment.month - issue.month);
    if (termMonths <= 0) {
      termMonths = 1;
    }

    List<InterestCharge> charges = [];
    final initialInterest = amountBorrowed * (interestRate / 100) * termMonths;

    int i = 0;
    final customPenaltyMap = getCustomPenaltyMap();

    while (true) {
      final anniversary = _getAnniversaryDate(repayment, i);
      if (anniversary.isAfter(evalDate)) {
        break;
      }

      final dateStr = DateFormat('MM/dd/yyyy').format(anniversary);
      final isWaived = waivedSet.contains(dateStr);

      final principalPaidBeforeOrOn = payments
          .where((p) => p.paymentType == 'Loan Principal' && p.status == 'paid')
          .where((p) {
            try {
              final pDate = _parseDateSafe(p.paymentDate);
              if (pDate == null) return false;
              return pDate.isBefore(anniversary) || _isSameDay(pDate, anniversary);
            } catch (_) {
              return false;
            }
          })
          .fold<double>(0.0, (sum, p) => sum + p.amount);

      final remainingPrincipal = max(0.0, amountBorrowed - principalPaidBeforeOrOn);

      // Penalties only start at i > 0, and stop once the remaining principal is paid.
      if (i > 0 && remainingPrincipal <= 0.01) {
        break;
      }

      final double chargeAmount;
      final String label;

      if (i == 0) {
        chargeAmount = initialInterest;
        label = "Initial Interest";
      } else {
        if (customPenaltyMap.containsKey(dateStr)) {
          chargeAmount = customPenaltyMap[dateStr]!;
        } else {
          chargeAmount = remainingPrincipal * (interestRate / 100);
        }
        label = "Late Penalty (Month $i)";
      }

      double allocatedPaid = 0.0;
      if (!isWaived) {
        if (i == 0) {
          // Initial interest is paid from interestPaid (type 'Interest' / 'Maturity Collection')
          allocatedPaid = min(interestPaid, chargeAmount);
        } else {
          // Late penalties are paid from specific payments of type 'Penalty' or 'Late Fee' targeting this month
          final penaltyPaidForThisMonth = payments
              .where((p) => (p.paymentType == 'Penalty' || p.paymentType == 'Late Fee') && p.status == 'paid')
              .where((p) => p.notes == 'Penalty: $dateStr')
              .fold<double>(0.0, (sum, p) => sum + p.amount);
          allocatedPaid = min(penaltyPaidForThisMonth, chargeAmount);
        }
      }

      if (chargeAmount > 0 || i == 0) {
        charges.add(InterestCharge(
          date: anniversary,
          totalAmount: chargeAmount,
          paidAmount: allocatedPaid,
          label: label,
          isWaived: isWaived,
        ));
      }

      i++;
    }

    return charges;
  }

  double calculateTotalUnpaidInterest(List<Payment> payments, {DateTime? evaluationDate}) {
    final charges = calculateInterestCharges(payments, evaluationDate: evaluationDate);
    return charges.fold<double>(0.0, (sum, c) => sum + c.unpaidAmount);
  }

  double calculateMaturityBalance(List<Payment> payments, {DateTime? evaluationDate}) {
    if (isOneTimeInterest) {
      return amountBorrowed + interestRate;
    }
    final charges = calculateInterestCharges(payments, evaluationDate: evaluationDate);
    final totalInterest = charges.where((c) => !c.isWaived).fold<double>(0.0, (sum, c) => sum + c.totalAmount);
    return amountBorrowed + totalInterest;
  }

  double calculateTotalInterestAndPenalties(List<Payment> payments, {DateTime? evaluationDate}) {
    if (isOneTimeInterest) {
      return interestRate;
    }
    final charges = calculateInterestCharges(payments, evaluationDate: evaluationDate);
    return charges.where((c) => !c.isWaived).fold<double>(0.0, (sum, c) => sum + c.totalAmount);
  }

  double calculateRemainingPrincipal(List<Payment> payments) {
    final principalPaid = payments
        .where((p) => p.paymentType == 'Loan Principal' && p.status == 'paid')
        .fold<double>(0.0, (sum, p) => sum + p.amount);
    return max(0.0, amountBorrowed - principalPaid);
  }
}
