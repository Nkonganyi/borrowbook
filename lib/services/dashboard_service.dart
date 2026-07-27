import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> getStats() async {
    final customers = await supabase.from('customers').select();
    final borrowItems = await supabase.from('borrow_items').select();

    double outstandingDebt = 0;
    int overdueCount = 0;
    final now = DateTime.now();

    for (var item in borrowItems) {
      if (item['is_paid'] == false) {
        outstandingDebt += double.parse(item['price'].toString());
        
        // Calculate overdue status
        final createdAt = DateTime.parse(item['created_at']);
        final difference = now.difference(createdAt).inDays;
        if (difference >= 7) {
          overdueCount++;
        }
      }
    }

    final customersOwingIds = borrowItems
        .where((item) => item['is_paid'] == false)
        .map((item) => item['customer_id'])
        .toSet();

    final overdueCustomersIds = borrowItems
        .where((item) => item['is_paid'] == false)
        .where((item) {
          final createdAt = DateTime.parse(item['created_at']);
          return now.difference(createdAt).inDays >= 7;
        })
        .map((item) => item['customer_id'])
        .toSet();

    return {
      'totalCustomers': customers.length,
      'outstandingDebt': outstandingDebt,
      'customersOwing': customersOwingIds.length,
      'overdueCustomers': overdueCustomersIds.length,
    };
  }
}
