import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

/// Queues writes that couldn't reach Supabase (no internet) and replays
/// them, in order, the moment connectivity comes back.
///
/// Deliberately table-generic — an operation is just "insert this row(s)
/// into this table", "update this row", or "delete this row" — rather than
/// each service knowing how to serialize itself into the queue. This keeps
/// CustomerService/BorrowService/PaymentService as the only things that
/// know their own shape, and avoids circular imports between services.
class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  static const _storageKey = 'pending_operations';
  final supabase = Supabase.instance.client;

  bool _isProcessing = false;

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(queue));
  }

  Future<int> pendingCount() async => (await _readQueue()).length;

  Future<List<Map<String, dynamic>>> getQueueSnapshot() => _readQueue();

  /// [action] is one of: 'insert', 'insert_many', 'update', 'delete'.
  /// [notifyTitle]/[notifyBody] are optional — if set, a push notification
  /// is sent to the other sellers once this operation actually syncs
  /// (never while it's just sitting in the queue offline).
  Future<void> enqueue({
    required String table,
    required String action,
    Map<String, dynamic>? data,
    List<Map<String, dynamic>>? rows,
    String? rowId,
    String? notifyTitle,
    String? notifyBody,
  }) async {
    final queue = await _readQueue();
    queue.add({
      'id': 'op-${DateTime.now().microsecondsSinceEpoch}',
      'table': table,
      'action': action,
      'data': data,
      'rows': rows,
      'row_id': rowId,
      'notify_title': notifyTitle,
      'notify_body': notifyBody,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _writeQueue(queue);
  }

  /// Replays every queued operation. An operation that still fails (still
  /// offline, or a genuine error) is left in the queue for next time;
  /// everything else that succeeds is removed. Safe to call repeatedly —
  /// re-entrant calls while already processing are ignored.
  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final queue = await _readQueue();
      if (queue.isEmpty) return;

      final stillPending = <Map<String, dynamic>>[];

      for (final op in queue) {
        try {
          await _execute(op);
        } catch (_) {
          stillPending.add(op);
        }
      }

      await _writeQueue(stillPending);
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _execute(Map<String, dynamic> op) async {
    final table = op['table'] as String;
    final action = op['action'] as String;

    switch (action) {
      case 'insert':
        await supabase.from(table).insert(Map<String, dynamic>.from(op['data']));
        break;
      case 'insert_many':
        final rows = (op['rows'] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        await supabase.from(table).insert(rows);
        break;
      case 'update':
        await supabase
            .from(table)
            .update(Map<String, dynamic>.from(op['data']))
            .eq('id', op['row_id']);
        break;
      case 'delete':
        await supabase.from(table).delete().eq('id', op['row_id']);
        break;
      default:
        return; // unknown action, drop it rather than retry forever
    }

    final title = op['notify_title'] as String?;
    final body = op['notify_body'] as String?;
    if (title != null && body != null) {
      // Best-effort — a failed notification shouldn't cause the write
      // itself (which already succeeded above) to be re-queued.
      try {
        await NotificationService().sendPushNotification(title: title, body: body);
      } catch (_) {}
    }
  }
}
