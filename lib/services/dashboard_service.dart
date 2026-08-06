import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_cache_service.dart';

class DashboardService {
  final supabase = Supabase.instance.client;
  static const _cacheKey = 'dashboard_stats_cache';
  static const _extendedCacheKey = 'dashboard_extended_cache';

  /// Sums how much has already been paid against each borrow item, so
  /// "outstanding" reflects partial payments correctly instead of only
  /// looking at the all-or-nothing is_paid flag.
  Map<String, double> _paidByItem(List payments) {
    final map = <String, double>{};
    for (var p in payments) {
      final itemId = p['borrow_item_id'];
      if (itemId == null) continue;
      final amount = double.parse(p['amount'].toString());
      map[itemId] = (map[itemId] ?? 0) + amount;
    }
    return map;
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      final customers = await supabase.from('customers').select().timeout(const Duration(seconds: 8));
      final borrowItems = await supabase.from('borrow_items').select().timeout(const Duration(seconds: 8));
      final payments = await supabase.from('payments').select('borrow_item_id, amount').timeout(const Duration(seconds: 8));

      final paidByItem = _paidByItem(payments);

      double outstandingDebt = 0;
      final now = DateTime.now();
      final customersOwingIds = <String>{};
      final overdueCustomersIds = <String>{};

      for (var item in borrowItems) {
        final price = double.parse(item['price'].toString());
        final paidSoFar = paidByItem[item['id']] ?? 0;
        final remaining = price - paidSoFar;

        if (remaining > 0) {
          outstandingDebt += remaining;
          customersOwingIds.add(item['customer_id']);

          final createdAt = DateTime.parse(item['created_at']);
          final difference = now.difference(createdAt).inDays;
          if (difference >= 7) {
            overdueCustomersIds.add(item['customer_id']);
          }
        }
      }

      final stats = {
        'totalCustomers': customers.length,
        'outstandingDebt': outstandingDebt,
        'customersOwing': customersOwingIds.length,
        'overdueCustomers': overdueCustomersIds.length,
      };

      await LocalCacheService().saveMap(_cacheKey, stats);
      return stats;
    } catch (_) {
      // No/slow internet — show the last known numbers rather than
      // throwing and leaving the dashboard card stuck loading forever.
      final cached = await LocalCacheService().loadMap(_cacheKey);
      return cached ??
          {
            'totalCustomers': 0,
            'outstandingDebt': 0,
            'customersOwing': 0,
            'overdueCustomers': 0,
          };
    }
  }

  /// Roadmap P2: extended statistics, weekly borrowed-vs-collected series
  /// (for the chart), top debtors, and the aging ("who to chase first")
  /// report — balance × days overdue, not balance alone.
  Future<Map<String, dynamic>> getExtendedStats() async {
    try {
      final customers = await supabase.from('customers').select().timeout(const Duration(seconds: 8));
      final borrowItems = await supabase.from('borrow_items').select().timeout(const Duration(seconds: 8));
      final payments = await supabase.from('payments').select().timeout(const Duration(seconds: 8));

      final customerLookup = <String, Map<String, dynamic>>{
        for (var c in customers) c['id'] as String: Map<String, dynamic>.from(c),
      };

      final paidByItem = _paidByItem(payments);
      final now = DateTime.now();

      // --- Outstanding balance + oldest-unpaid-days per customer ---
      final balanceByCustomer = <String, double>{};
      final oldestUnpaidDaysByCustomer = <String, int>{};

      for (var item in borrowItems) {
        final price = double.parse(item['price'].toString());
        final paidSoFar = paidByItem[item['id']] ?? 0;
        final remaining = price - paidSoFar;
        if (remaining <= 0) continue;

        final customerId = item['customer_id'] as String;
        balanceByCustomer[customerId] = (balanceByCustomer[customerId] ?? 0) + remaining;

        final createdAt = DateTime.parse(item['created_at']);
        final days = now.difference(createdAt).inDays;
        if (days > (oldestUnpaidDaysByCustomer[customerId] ?? 0)) {
          oldestUnpaidDaysByCustomer[customerId] = days;
        }
      }

      // --- Top 5 debtors by balance ---
      final sortedByBalance = balanceByCustomer.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topDebtors = sortedByBalance.take(5).map((e) {
        return {
          'customerId': e.key,
          'name': customerLookup[e.key]?['name'] ?? 'Unknown',
          'balance': e.value,
          'customer': customerLookup[e.key],
        };
      }).toList();

      // --- Aging report: balance × days overdue, "who to chase first" ---
      final aging = balanceByCustomer.entries.map((e) {
        final days = oldestUnpaidDaysByCustomer[e.key] ?? 0;
        return {
          'customerId': e.key,
          'name': customerLookup[e.key]?['name'] ?? 'Unknown',
          'balance': e.value,
          'daysOverdue': days,
          'score': e.value * days,
          'customer': customerLookup[e.key],
        };
      }).toList()
        ..sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
      final agingTop = aging.take(10).toList();

      // --- Collected this week / month ---
      final weekAgo = now.subtract(const Duration(days: 7));
      final monthAgo = now.subtract(const Duration(days: 30));
      double collectedThisWeek = 0;
      double collectedThisMonth = 0;
      for (var p in payments) {
        final createdAt = DateTime.parse(p['created_at']);
        final amount = double.parse(p['amount'].toString());
        if (!createdAt.isBefore(weekAgo)) collectedThisWeek += amount;
        if (!createdAt.isBefore(monthAgo)) collectedThisMonth += amount;
      }

      // --- Average days to fully pay off an item (only fully-paid items) ---
      final paidItems = borrowItems.where((i) => i['is_paid'] == true && i['paid_at'] != null);
      double totalDays = 0;
      int paidCount = 0;
      for (var item in paidItems) {
        final createdAt = DateTime.parse(item['created_at']);
        final paidAt = DateTime.parse(item['paid_at']);
        totalDays += paidAt.difference(createdAt).inHours / 24.0;
        paidCount++;
      }
      final avgDaysToPay = paidCount > 0 ? totalDays / paidCount : 0.0;

      // --- Weekly series (last 6 weeks) for the chart: borrowed vs collected ---
      final weeklySeries = <Map<String, dynamic>>[];
      for (int w = 5; w >= 0; w--) {
        final weekStart = now.subtract(Duration(days: (w + 1) * 7));
        final weekEnd = now.subtract(Duration(days: w * 7));

        double borrowed = 0;
        for (var item in borrowItems) {
          final createdAt = DateTime.parse(item['created_at']);
          if (!createdAt.isBefore(weekStart) && createdAt.isBefore(weekEnd)) {
            borrowed += double.parse(item['price'].toString());
          }
        }

        double collected = 0;
        for (var p in payments) {
          final createdAt = DateTime.parse(p['created_at']);
          if (!createdAt.isBefore(weekStart) && createdAt.isBefore(weekEnd)) {
            collected += double.parse(p['amount'].toString());
          }
        }

        weeklySeries.add({
          'label': 'W${6 - w}',
          'borrowed': borrowed,
          'collected': collected,
        });
      }

      final result = {
        'collectedThisWeek': collectedThisWeek,
        'collectedThisMonth': collectedThisMonth,
        'avgDaysToPay': avgDaysToPay,
        'topDebtors': topDebtors,
        'aging': agingTop,
        'weeklySeries': weeklySeries,
      };

      await LocalCacheService().saveMap(_extendedCacheKey, result);
      return result;
    } catch (_) {
      final cached = await LocalCacheService().loadMap(_extendedCacheKey);
      return cached ??
          {
            'collectedThisWeek': 0.0,
            'collectedThisMonth': 0.0,
            'avgDaysToPay': 0.0,
            'topDebtors': [],
            'aging': [],
            'weeklySeries': [],
          };
    }
  }
}
