class InterestCharge {
  final DateTime date;
  final double totalAmount;
  final double paidAmount;
  final String label;
  final bool isWaived;

  double get unpaidAmount => isWaived ? 0.0 : totalAmount - paidAmount;
  bool get isPaid => isWaived || unpaidAmount <= 0.001;

  InterestCharge({
    required this.date,
    required this.totalAmount,
    required this.paidAmount,
    required this.label,
    this.isWaived = false,
  });
}
