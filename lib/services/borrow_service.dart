import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

class BorrowService {
  final supabase = Supabase.instance.client;

  Future<void> addBorrowItems(List<Map<String, dynamic>> items, {required String customerName, required String addedBy}) async {
    await supabase.from('borrow_items').insert(items);
    
    if (items.isNotEmpty) {
      String itemSummary = items.map((i) => "${i['item_name']} (${i['price']} FCFA)").join(", ");
      await NotificationService().sendPushNotification(
        title: '🔔 New Debt Recorded',
        body: 'Customer: $customerName\nItems: $itemSummary\nRecorded by: $addedBy',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getBorrowItems(String customerId) async {
    final data = await supabase
        .from('borrow_items')
        .select()
        .eq('customer_id', customerId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getAllUnpaidItems() async {
    final data = await supabase
        .from('borrow_items')
        .select()
        .eq('is_paid', false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> updateBorrowItem({
    required String itemId,
    required String itemName,
    required double price,
    required String oldItemName,
    required double oldPrice,
    required String editedBy,
  }) async {
    await supabase
        .from('borrow_items')
        .update({
          'item_name': itemName,
          'price': price,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', itemId);

    await NotificationService().sendPushNotification(
      title: '✏️ Debt Edited',
      body: 'Seller: $editedBy updated item: $oldItemName ($oldPrice FCFA) to $itemName ($price FCFA)',
    );
  }

  Future<void> deleteBorrowItem(String itemId) async {
    await supabase.from('borrow_items').delete().eq('id', itemId);
  }

  Future<void> markAsPaid(String itemId, {required String paidBy, required String itemName, required String customerName}) async {
    await supabase.from('borrow_items').update({
      'is_paid': true,
      'paid_by': paidBy,
      'paid_at': DateTime.now().toIso8601String(),
    }).eq('id', itemId);

    await NotificationService().sendPushNotification(
      title: '✅ Payment Received',
      body: 'Seller: $paidBy received payment for $itemName from $customerName',
    );
  }

  /// Checks for any items that have been unpaid for 7+ days and sends an alert.
  Future<void> checkAndNotifyOverdue() async {
    final now = DateTime.now();
    // Only fetch items that are unpaid and haven't been notified yet
    final unpaid = await supabase
        .from('borrow_items')
        .select('*, customers(name)')
        .eq('is_paid', false)
        .eq('overdue_notified', false);
    
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
  }
}
