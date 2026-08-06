import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'payment_service.dart';
import 'connectivity_service.dart';
import 'local_cache_service.dart';
import 'offline_queue_service.dart';

class BorrowService {
  final supabase = Supabase.instance.client;

  /// Returns true if queued for later sync, false if it reached Supabase
  /// immediately.
  Future<bool> addBorrowItems(
    List<Map<String, dynamic>> items, {
    required String customerName,
    required String addedBy,
  }) async {
    if (items.isEmpty) return false;
    final customerId = items.first['customer_id'] as String;
    final itemSummary = items.map((i) => "${i['item_name']} (${i['price']} FCFA)").join(", ");

    final online = await ConnectivityService().isOnline();
    if (online) {
      try {
        await supabase.from('borrow_items').insert(items).timeout(const Duration(seconds: 10));
        await NotificationService().sendPushNotification(
          title: '🔔 New Debt Recorded',
          body: 'Customer: $customerName\nItems: $itemSummary\nRecorded by: $addedBy',
        );
        return false;
      } catch (_) {
        // fall through to queue
      }
    }

    await OfflineQueueService().enqueue(
      table: 'borrow_items',
      action: 'insert_many',
      rows: items,
      notifyTitle: '🔔 New Debt Recorded',
      notifyBody: 'Customer: $customerName\nItems: $itemSummary\nRecorded by: $addedBy',
    );

    // Optimistic local cache update so the items show up immediately.
    final cacheKey = 'borrow_items_cache_$customerId';
    final cached = await LocalCacheService().loadList(cacheKey) ?? [];
    for (final item in items) {
      cached.add({
        ...item,
        'id': 'local-${DateTime.now().microsecondsSinceEpoch}-${cached.length}',
        'created_at': DateTime.now().toIso8601String(),
        '_pendingSync': true,
      });
    }
    await LocalCacheService().saveList(cacheKey, cached);

    return true;
  }

  Future<List<Map<String, dynamic>>> getBorrowItems(String customerId) async {
    final cacheKey = 'borrow_items_cache_$customerId';
    try {
      final data = await supabase
          .from('borrow_items')
          .select()
          .eq('customer_id', customerId)
          .order('created_at')
          .timeout(const Duration(seconds: 8));

      final list = List<Map<String, dynamic>>.from(data);
      await LocalCacheService().saveList(cacheKey, list);
      return list;
    } catch (_) {
      final cached = await LocalCacheService().loadList(cacheKey);
      return cached ?? [];
    }
  }

  Future<List<Map<String, dynamic>>> getAllUnpaidItems() async {
    const cacheKey = 'unpaid_items_cache';
    try {
      final data = await supabase
          .from('borrow_items')
          .select()
          .eq('is_paid', false)
          .timeout(const Duration(seconds: 8));

      final list = List<Map<String, dynamic>>.from(data);
      await LocalCacheService().saveList(cacheKey, list);
      return list;
    } catch (_) {
      final cached = await LocalCacheService().loadList(cacheKey);
      return cached ?? [];
    }
  }

  /// Logs a correction/void to borrow_item_changes (Roadmap P1.3).
  /// Append-only — this is a record of what happened, never itself edited.
  Future<void> logChange({
    String? borrowItemId,
    required String customerId,
    required String action, // 'edit' or 'delete'
    required String reason,
    required String changedBy,
    String? oldItemName,
    double? oldPrice,
    String? newItemName,
    double? newPrice,
  }) async {
    await supabase.from('borrow_item_changes').insert({
      'borrow_item_id': borrowItemId,
      'customer_id': customerId,
      'action': action,
      'reason': reason,
      'changed_by': changedBy,
      'old_item_name': oldItemName,
      'old_price': oldPrice,
      'new_item_name': newItemName,
      'new_price': newPrice,
    });
  }

  /// Returns true if queued for later sync, false if it reached Supabase
  /// immediately. Edit/delete/change-log writes are lower-frequency and
  /// touch financial-correction records, so unlike adds/payments we queue
  /// them as a single unit (log + mutation) rather than trying to be
  /// clever about partial offline application.
  Future<bool> updateBorrowItem({
    required String itemId,
    required String customerId,
    required String itemName,
    required double price,
    required String oldItemName,
    required double oldPrice,
    required String editedBy,
    // Only required by the UI when the item already has payments recorded
    // against it — see customer_details_screen.dart.
    String? reason,
  }) async {
    final updateData = {
      'item_name': itemName,
      'price': price,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final online = await ConnectivityService().isOnline();
    if (online) {
      try {
        if (reason != null && reason.trim().isNotEmpty) {
          await logChange(
            borrowItemId: itemId,
            customerId: customerId,
            action: 'edit',
            reason: reason.trim(),
            changedBy: editedBy,
            oldItemName: oldItemName,
            oldPrice: oldPrice,
            newItemName: itemName,
            newPrice: price,
          );
        }
        await supabase.from('borrow_items').update(updateData).eq('id', itemId).timeout(const Duration(seconds: 10));
        await NotificationService().sendPushNotification(
          title: '✏️ Debt Edited',
          body: 'Seller: $editedBy updated item: $oldItemName ($oldPrice FCFA) to $itemName ($price FCFA)',
        );
        return false;
      } catch (_) {
        // fall through to queue
      }
    }

    if (reason != null && reason.trim().isNotEmpty) {
      await OfflineQueueService().enqueue(
        table: 'borrow_item_changes',
        action: 'insert',
        data: {
          'borrow_item_id': itemId,
          'customer_id': customerId,
          'action': 'edit',
          'reason': reason.trim(),
          'changed_by': editedBy,
          'old_item_name': oldItemName,
          'old_price': oldPrice,
          'new_item_name': itemName,
          'new_price': price,
        },
      );
    }

    await OfflineQueueService().enqueue(
      table: 'borrow_items',
      action: 'update',
      rowId: itemId,
      data: updateData,
      notifyTitle: '✏️ Debt Edited',
      notifyBody: 'Seller: $editedBy updated item: $oldItemName ($oldPrice FCFA) to $itemName ($price FCFA)',
    );

    // Optimistic local cache update
    final cacheKey = 'borrow_items_cache_$customerId';
    final cached = await LocalCacheService().loadList(cacheKey);
    if (cached != null) {
      final idx = cached.indexWhere((i) => i['id'] == itemId);
      if (idx != -1) {
        cached[idx] = {...cached[idx], ...updateData, '_pendingSync': true};
        await LocalCacheService().saveList(cacheKey, cached);
      }
    }

    return true;
  }

  /// Returns true if queued for later sync, false if it reached Supabase
  /// immediately.
  Future<bool> deleteBorrowItem(
    String itemId, {
    String? customerId,
    String? changedBy,
    String? reason,
    String? itemName,
    double? price,
  }) async {
    final online = await ConnectivityService().isOnline();
    if (online) {
      try {
        if (reason != null && reason.trim().isNotEmpty && customerId != null) {
          await logChange(
            borrowItemId: itemId,
            customerId: customerId,
            action: 'delete',
            reason: reason.trim(),
            changedBy: changedBy ?? 'Unknown',
            oldItemName: itemName,
            oldPrice: price,
          );
        }
        await supabase.from('borrow_items').delete().eq('id', itemId).timeout(const Duration(seconds: 10));
        return false;
      } catch (_) {
        // fall through to queue
      }
    }

    if (reason != null && reason.trim().isNotEmpty && customerId != null) {
      await OfflineQueueService().enqueue(
        table: 'borrow_item_changes',
        action: 'insert',
        data: {
          'borrow_item_id': itemId,
          'customer_id': customerId,
          'action': 'delete',
          'reason': reason.trim(),
          'changed_by': changedBy ?? 'Unknown',
          'old_item_name': itemName,
          'old_price': price,
        },
      );
    }

    await OfflineQueueService().enqueue(table: 'borrow_items', action: 'delete', rowId: itemId);

    // Optimistic local cache update
    if (customerId != null) {
      final cacheKey = 'borrow_items_cache_$customerId';
      final cached = await LocalCacheService().loadList(cacheKey);
      if (cached != null) {
        cached.removeWhere((i) => i['id'] == itemId);
        await LocalCacheService().saveList(cacheKey, cached);
      }
    }

    return true;
  }

  /// Pays off the FULL remaining balance on this item in one shot, by
  /// recording a payment through the ledger (payments table) rather than
  /// flipping is_paid directly — the DB trigger derives is_paid from the
  /// sum of payments once it reaches the item's price. For partial amounts,
  /// call PaymentService.addPayment directly with a specific amount instead.
  ///
  /// Note: this specifically needs to read the item's current price and
  /// payment total from the server first, so — unlike the other methods
  /// here — it still requires connectivity. The UI's "Record Payment"
  /// dialog (which already has this data loaded client-side) is the
  /// offline-safe path; prefer that over this method when possible.
  Future<void> markAsPaid(String itemId, {required String paidBy, required String itemName, required String customerName}) async {
    final item = await supabase.from('borrow_items').select().eq('id', itemId).single();
    final price = double.parse(item['price'].toString());

    final paidRows = await supabase.from('payments').select('amount').eq('borrow_item_id', itemId);
    final paidSoFar = (paidRows as List)
        .fold<double>(0, (sum, row) => sum + double.parse(row['amount'].toString()));

    final remaining = price - paidSoFar;
    if (remaining <= 0) return; // already fully paid, nothing to record

    await PaymentService().addPayment(
      customerId: item['customer_id'],
      borrowItemId: itemId,
      amount: remaining,
      paidBy: paidBy,
      customerName: customerName,
      itemName: itemName,
    );
  }

  /// Checks for any items that have been unpaid for 7+ days and sends an alert.
  Future<void> checkAndNotifyOverdue() async {
    final now = DateTime.now();
    try {
      // Only fetch items that are unpaid and haven't been notified yet
      final unpaid = await supabase
          .from('borrow_items')
          .select('*, customers(name)')
          .eq('is_paid', false)
          .eq('overdue_notified', false)
          .timeout(const Duration(seconds: 8));

      for (var item in unpaid) {
        final createdAt = DateTime.parse(item['created_at']);
        final days = now.difference(createdAt).inDays;

        if (days >= 7) {
          final customerName = item['customers']['name'] ?? 'Unknown Customer';

          await NotificationService().sendPushNotification(
            title: '⚠️ OVERDUE ALERT',
            body: 'Customer $customerName is now $days days overdue for ${item['item_name']}!',
          );

          // Mark as notified so we don't send it again until next check
          await supabase.from('borrow_items').update({'overdue_notified': true}).eq('id', item['id']);
        }
      }
    } catch (_) {
      // No connectivity right now — this is a periodic check, it'll just
      // run again next time the app is opened online. Nothing to queue.
    }
  }
}
