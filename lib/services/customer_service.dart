import 'package:supabase_flutter/supabase_flutter.dart';
import 'connectivity_service.dart';
import 'local_cache_service.dart';
import 'offline_queue_service.dart';

class CustomerService {
  final supabase = Supabase.instance.client;
  static const _cacheKey = 'customers_cache';

  /// Returns true if the write was queued for later sync (no internet right
  /// now), false if it reached Supabase immediately.
  Future<bool> addCustomer({
    required String name,
    required String phone,
    required String location,
    required String notes,
  }) async {
    final data = {
      'name': name,
      'phone': phone,
      'location': location,
      'notes': notes,
    };

    final online = await ConnectivityService().isOnline();
    if (online) {
      try {
        await supabase.from('customers').insert(data).timeout(const Duration(seconds: 10));
        return false;
      } catch (_) {
        // Had a signal but the request itself failed/timed out — treat the
        // same as offline rather than losing the customer's entry.
      }
    }

    await OfflineQueueService().enqueue(table: 'customers', action: 'insert', data: data);

    // Optimistic local update so the customer shows up immediately even
    // though it hasn't reached the server yet.
    await LocalCacheService().prependToList(_cacheKey, {
      ...data,
      'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
      'created_at': DateTime.now().toIso8601String(),
      '_pendingSync': true,
    });

    return true;
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    try {
      final data = await supabase
          .from('customers')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      final list = List<Map<String, dynamic>>.from(data);
      await LocalCacheService().saveList(_cacheKey, list);
      return list;
    } catch (_) {
      // No/slow internet — fall back to whatever we last saw, instead of
      // throwing and leaving the screen blank or crashed.
      final cached = await LocalCacheService().loadList(_cacheKey);
      return cached ?? [];
    }
  }
}
