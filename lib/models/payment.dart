class Payment {
  final int? id;
  final int borrowerId;
  final double amount;
  final String paymentType; // 'Interest', 'Loan Principal', 'Late Fee', 'Credit'
  final String paymentDate;
  final String? notes;
  final String status; // 'paid', 'credited'
  final String updatedAt;

  Payment({
    this.id,
    required this.borrowerId,
    required this.amount,
    required this.paymentType,
    required this.paymentDate,
    this.notes,
    this.status = 'paid',
    String? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'borrowerId': borrowerId,
        'amount': amount,
        'paymentType': paymentType,
        'paymentDate': paymentDate,
        'notes': notes,
        'status': status,
        'updatedAt': updatedAt,
      };

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
        id: map['id'] is int ? map['id'] : (int.tryParse(map['id']?.toString() ?? '')),
        borrowerId: map['borrowerId'] is int
            ? map['borrowerId']
            : (int.tryParse(map['borrowerId']?.toString() ?? '') ?? 0),
        amount: map['amount'] != null
            ? (double.tryParse(map['amount'].toString()) ?? 0.0)
            : 0.0,
        paymentType: map['paymentType']?.toString() ?? 'Interest',
        paymentDate: map['paymentDate']?.toString() ?? '',
        notes: map['notes']?.toString(),
        status: map['status']?.toString() ?? 'paid',
        updatedAt: map['updatedAt']?.toString() ?? '',
      );

  Payment copyWith({
    int? id,
    int? borrowerId,
    double? amount,
    String? paymentType,
    String? paymentDate,
    String? notes,
    String? status,
    String? updatedAt,
  }) =>
      Payment(
        id: id ?? this.id,
        borrowerId: borrowerId ?? this.borrowerId,
        amount: amount ?? this.amount,
        paymentType: paymentType ?? this.paymentType,
        paymentDate: paymentDate ?? this.paymentDate,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
