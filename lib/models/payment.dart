class Payment {
  final int? id;
  final int borrowerId;
  final double amount;
  final String paymentType; // 'Interest', 'Loan Principal', 'Late Fee', 'Credit'
  final String paymentDate;
  final String? notes;
  final String status; // 'paid', 'credited'

  Payment({
    this.id,
    required this.borrowerId,
    required this.amount,
    required this.paymentType,
    required this.paymentDate,
    this.notes,
    this.status = 'paid',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'borrowerId': borrowerId,
        'amount': amount,
        'paymentType': paymentType,
        'paymentDate': paymentDate,
        'notes': notes,
        'status': status,
      };

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
        id: map['id'],
        borrowerId: map['borrowerId'],
        amount: map['amount'],
        paymentType: map['paymentType'],
        paymentDate: map['paymentDate'],
        notes: map['notes'],
        status: map['status'] ?? 'paid',
      );

  Payment copyWith({
    int? id,
    int? borrowerId,
    double? amount,
    String? paymentType,
    String? paymentDate,
    String? notes,
    String? status,
  }) =>
      Payment(
        id: id ?? this.id,
        borrowerId: borrowerId ?? this.borrowerId,
        amount: amount ?? this.amount,
        paymentType: paymentType ?? this.paymentType,
        paymentDate: paymentDate ?? this.paymentDate,
        notes: notes ?? this.notes,
        status: status ?? this.status,
      );
}
