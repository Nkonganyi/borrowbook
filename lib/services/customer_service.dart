import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerService {
  final supabase = Supabase.instance.client;

  Future<void> addCustomer({
    required String name,
    required String phone,
    required String location,
    required String notes,
  }) async {
    await supabase.from('customers').insert({
      'name': name,
      'phone': phone,
      'location': location,
      'notes': notes,
    });
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final data = await supabase
        .from('customers')
        .select()
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }
}