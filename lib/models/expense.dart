class Expense {
  final int? id;
  final String name;
  final double amount;
  final String category;
  final String date; // Format: MM/dd/yyyy
  final String? notes;
  final String type; // 'expense' or 'income'
  final String status; // 'completed' or 'pending'
  final bool isUrgent;

  Expense({
    this.id,
    required this.name,
    required this.amount,
    required this.category,
    required this.date,
    this.notes,
    this.type = 'expense',
    this.status = 'completed',
    this.isUrgent = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'amount': amount,
        'category': category,
        'date': date,
        'notes': notes,
        'type': type,
        'status': status,
        'isUrgent': isUrgent ? 1 : 0,
      };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'],
        name: map['name'],
        amount: map['amount']?.toDouble() ?? 0.0,
        category: map['category'] ?? '',
        date: map['date'] ?? '',
        notes: map['notes'],
        type: map['type'] ?? 'expense',
        status: map['status'] ?? 'completed',
        isUrgent: (map['isUrgent'] ?? 0) == 1,
      );

  Expense copyWith({
    int? id,
    String? name,
    double? amount,
    String? category,
    String? date,
    String? notes,
    String? type,
    String? status,
    bool? isUrgent,
  }) =>
      Expense(
        id: id ?? this.id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        category: category ?? this.category,
        date: date ?? this.date,
        notes: notes ?? this.notes,
        type: type ?? this.type,
        status: status ?? this.status,
        isUrgent: isUrgent ?? this.isUrgent,
      );
}
