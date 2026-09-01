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
  final String updatedAt;

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
    String? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc().toIso8601String();

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
        'updatedAt': updatedAt,
      };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'] is int ? map['id'] : (int.tryParse(map['id']?.toString() ?? '')),
        name: map['name']?.toString() ?? '',
        amount: map['amount'] != null
            ? (double.tryParse(map['amount'].toString()) ?? 0.0)
            : 0.0,
        category: map['category']?.toString() ?? 'General',
        date: map['date']?.toString() ?? '',
        notes: map['notes']?.toString(),
        type: map['type']?.toString() ?? 'expense',
        status: map['status']?.toString() ?? 'completed',
        isUrgent: map['isUrgent'] == 1 || map['isUrgent'] == true || map['isUrgent'] == '1',
        updatedAt: map['updatedAt']?.toString() ?? '',
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
    String? updatedAt,
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
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
