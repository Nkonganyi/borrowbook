import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

class AuthService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<AuthResponse> register({
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? role,
  }) async {
    final res = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );

    final user = res.user;
    if (user != null) {
      await supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': fullName ?? '',
        'phone': phone ?? '',
        'role': role ?? 'seller',
      });
      
      // Initialize notifications to capture token for the new user
      await NotificationService().init();
    }

    return res;
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final res = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    
    // Initialize notifications to capture token for the logged-in user
    await NotificationService().init();
    
    return res;
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
  }

  User? get currentUser => supabase.auth.currentUser;

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      return data;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateProfileName(String fullName) async {
    final user = currentUser;
    if (user == null) return;

    await supabase.auth.updateUser(
      UserAttributes(data: {'full_name': fullName}),
    );

    final profile = await getCurrentUserProfile();
    await supabase.from('profiles').upsert({
      'id': user.id,
      'full_name': fullName,
      'phone': profile?['phone'] ?? '',
      'role': profile?['role'] ?? 'seller',
    });
  }

  Future<String> getBestDisplayName() async {
    User? user = currentUser;
    try {
      final res = await supabase.auth.getUser();
      if (res.user != null) user = res.user;
    } catch (_) {}
    
    if (user == null) return 'Unknown User';

    try {
      final profile = await getCurrentUserProfile();
      if (profile != null && profile['full_name'] != null) {
        final name = profile['full_name'].toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}

    final String? metaName = user.userMetadata?['full_name'];
    if (metaName != null && metaName.trim().isNotEmpty) {
      return metaName.trim();
    }

    return user.email ?? 'Unknown User';
  }
}
