import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Tracks whether the device currently has a network connection, and fires
/// a callback the moment it comes back after being offline (used to trigger
/// OfflineQueueService.processQueue()).
///
/// Note: connectivity_plus reports whether a network *interface* is up
/// (wifi/mobile data connected) — not true internet reachability. You can
/// be "online" here while connected to wifi with no actual internet. The
/// authoritative check is still each service method's own try/catch with a
/// timeout; this class exists for fast pre-checks and UI banners.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _initialized = false;

  Future<void> init({VoidCallback? onBackOnline}) async {
    if (_initialized) return;
    _initialized = true;

    try {
      final initial = await _connectivity.checkConnectivity();
      isOnlineNotifier.value = _hasConnection(initial);
    } catch (_) {
      // If even checking connectivity fails, assume offline rather than crash.
      isOnlineNotifier.value = false;
    }

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOffline = !isOnlineNotifier.value;
      final nowOnline = _hasConnection(results);
      isOnlineNotifier.value = nowOnline;

      if (wasOffline && nowOnline) {
        onBackOnline?.call();
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// One-off check, used by service methods before attempting a write so
  /// they can skip straight to queuing instead of waiting out a timeout.
  Future<bool> isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _hasConnection(result);
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
