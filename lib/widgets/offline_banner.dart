import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';

/// Thin banner that appears automatically whenever the device is offline,
/// and disappears the moment connectivity returns. Drop it right under the
/// AppBar on any screen that reads or writes data.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService().isOnlineNotifier,
      builder: (context, isOnline, _) {
        if (isOnline) return const SizedBox.shrink();

        final finance = Theme.of(context).financeColors;

        return Container(
          width: double.infinity,
          color: finance.partial,
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  "Offline — showing last saved data. Changes will sync automatically.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
