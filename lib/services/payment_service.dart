import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_model.dart';
import 'notification_service.dart';

/// Ledger-based payment recording (Roadmap P0.1 / groundwork for P1).
///
/// This is intentionally append-only: there is no updatePayment or
/// deletePayment here on purpose (see the migration comment and P1.3 in the
/// roadmap — corrections should be a new reversal entry, not a mutation of
/// history).
class PaymentService {
  final supabase = Supabase.instance.client;

  /// Records a payment against a specific borrow item and pushes a
  /// notification to the other sellers, same pattern as
  /// BorrowService.markAsPaid.
  Future<Payment> addPayment({
    required String customerId,
    String? borrowItemId,
    required double amount,
    required String paidBy,
    String method = 'cash',
    String? note,
    String? customerName,
    String? itemName,
  }) async {
    final row = await supabase
        .from('payments')
        .insert({
          'customer_id': customerId,
          'borrow_item_id': borrowItemId,
          'amount': amount,
          'paid_by': paidBy,
          'method': method,
          'note': note,
        })
        .select()
        .single();

    final payment = Payment.fromJson(row);

    await NotificationService().sendPushNotification(
      title: '💰 Payment Recorded',
      body:
          '${paidBy} recorded ${amount.toStringAsFixed(0)} FCFA from ${customerName ?? "a customer"}'
          '${itemName != null ? " for $itemName" : ""}',
    );

    return payment;
  }

  /// Full payment history for a customer, most recent first.
  Future<List<Payment>> getPaymentsForCustomer(String customerId) async {
    final data = await supabase
        .from('payments')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    return (data as List).map((row) => Payment.fromJson(row)).toList();
  }

  /// Payment history for a single borrow item, most recent first.
  Future<List<Payment>> getPaymentsForItem(String borrowItemId) async {
    final data = await supabase
        .from('payments')
        .select()
        .eq('borrow_item_id', borrowItemId)
        .order('created_at', ascending: false);
    return (data as List).map((row) => Payment.fromJson(row)).toList();
  }

  /// Remaining balance on a single item: price minus everything paid
  /// against it so far. Useful for a "paid X of Y" display without waiting
  /// on the is_paid trigger round-trip.
  Future<double> getBalanceForItem({
    required String borrowItemId,
    required double price,
  }) async {
    final data = await supabase
        .from('payments')
        .select('amount')
        .eq('borrow_item_id', borrowItemId);

    final paid = (data as List)
        .fold<double>(0, (sum, row) => sum + double.parse(row['amount'].toString()));

    final balance = price - paid;
    return balance < 0 ? 0 : balance;
  }
}
