import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/offline_queue_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every step below is wrapped so a slow/absent connection can never
  // prevent the app from opening — at worst a step is skipped and retried
  // later once the device is back online.

  // 1. Firebase — needed for push notifications, not for the app to open.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('Firebase init skipped (offline or slow connection): $e');
  }

  // 2. Supabase — sets up the client locally; safe even with no internet.
  try {
    await Supabase.initialize(
      url: 'https://auzitwawlsuvhzeiqtgh.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF1eml0d2F3bHN1dmh6ZWlxdGdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA1NjM5NTUsImV4cCI6MjA5NjEzOTk1NX0.mhGGNiQ90WzWDpE8hyQ-tFO4k1F11NfX8e0ZIMQBANU',
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('Supabase init incomplete (offline or slow connection): $e');
  }

  // 3. Notifications — this used to be a bare `await` with no try/catch.
  // getToken()/subscribeToTopic() both hit the network with no timeout,
  // so with no internet this could hang or throw and runApp() below would
  // never execute — the app would just never open. Never let it block again.
  unawaited(
    NotificationService().init().timeout(
      const Duration(seconds: 15),
      onTimeout: () => debugPrint('Notification init timed out (offline) — continuing'),
    ).catchError((e) {
      debugPrint('Notification init failed (offline) — continuing: $e');
    }),
  );

  // 4. Start watching connectivity, and drain the offline write queue the
  // instant the device comes back online.
  await ConnectivityService().init(
    onBackOnline: () => OfflineQueueService().processQueue(),
  );
  // Also try once at cold start, in case there are ops queued from a
  // previous session and we're opening already-online.
  unawaited(OfflineQueueService().processQueue());

  await ThemeController().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeController.instance.mode,
          home: Supabase.instance.client.auth.currentSession != null
              ? const HomeScreen()
              : const LoginScreen(),
        );
      },
    );
  }
}
