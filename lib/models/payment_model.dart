class Payment {
  final String id;
  final String customerId;
  final String? borrowItemId;
  final double amount;
  final String paidBy;
  final String method;
  final String? note;
  final DateTime createdAt;

  Payment({
    required this.id,
    required this.customerId,
    this.borrowItemId,
    required this.amount,
    required this.paidBy,
    required this.method,
    this.note,
    required this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'],
      customerId: json['customer_id'],
      borrowItemId: json['borrow_item_id'],
      amount: double.parse(json['amount'].toString()),
      paidBy: json['paid_by'],
      method: json['method'] ?? 'cash',
      note: json['note'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
