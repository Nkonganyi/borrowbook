import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_model.dart';
import 'notification_service.dart';
import 'connectivity_service.dart';
import 'local_cache_service.dart';
import 'offline_queue_service.dart';

/// Ledger-based payment recording (Roadmap P0.1 / P1.1).
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
  ///
  /// Returns true if the payment was queued for later sync (no internet
  /// right now — the amount is still recorded locally and will reach the
  /// server once back online), false if it reached Supabase immediately.
  Future<bool> addPayment({
    required String customerId,
    String? borrowItemId,
    required double amount,
    required String paidBy,
    String method = 'cash',
    String? note,
    String? customerName,
    String? itemName,
  }) async {
    final data = {
      'customer_id': customerId,
      'borrow_item_id': borrowItemId,
      'amount': amount,
      'paid_by': paidBy,
      'method': method,
      'note': note,
    };

    final notifyTitle = '💰 Payment Recorded';
    final notifyBody =
        '$paidBy recorded ${amount.toStringAsFixed(0)} FCFA from ${customerName ?? "a customer"}'
        '${itemName != null ? " for $itemName" : ""}';

    final online = await ConnectivityService().isOnline();
    if (online) {
      try {
        await supabase.from('payments').insert(data).timeout(const Duration(seconds: 10));
        await NotificationService().sendPushNotification(title: notifyTitle, body: notifyBody);
        await _refreshCustomerCache(customerId);
        return false;
      } catch (_) {
        // fall through to queue
      }
    }

    await OfflineQueueService().enqueue(
      table: 'payments',
      action: 'insert',
      data: data,
      notifyTitle: notifyTitle,
      notifyBody: notifyBody,
    );

    // Optimistic local cache update — the payment shows up in the
    // Payment History tab and in "paid so far" calculations right away.
    final cacheKey = 'payments_cache_$customerId';
    await LocalCacheService().prependToList(cacheKey, {
      'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
      'customer_id': customerId,
      'borrow_item_id': borrowItemId,
      'amount': amount,
      'paid_by': paidBy,
      'method': method,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
      '_pendingSync': true,
    });

    return true;
  }

  Future<void> _refreshCustomerCache(String customerId) async {
    // Best-effort refresh so the cache doesn't go stale after a
    // successful online write; not critical if it fails.
    try {
      await getPaymentsForCustomer(customerId);
    } catch (_) {}
  }

  /// Full payment history for a customer, most recent first.
  Future<List<Payment>> getPaymentsForCustomer(String customerId) async {
    final cacheKey = 'payments_cache_$customerId';
    try {
      final data = await supabase
          .from('payments')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      final rows = List<Map<String, dynamic>>.from(data);
      await LocalCacheService().saveList(cacheKey, rows);
      return rows.map((row) => Payment.fromJson(row)).toList();
    } catch (_) {
      final cached = await LocalCacheService().loadList(cacheKey);
      if (cached == null) return [];
      // Locally-queued rows use a placeholder amount type that's already
      // a double/num from Dart, same as Payment.fromJson expects.
      return cached.map((row) => Payment.fromJson(row)).toList();
    }
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
