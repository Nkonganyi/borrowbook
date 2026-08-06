import 'package:flutter/material.dart';
import '../services/borrow_service.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../models/payment_model.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_banner.dart';
import '../widgets/animated_money.dart';
import '../widgets/receipt_tear_divider.dart';
import '../widgets/fade_in_item.dart';
import 'add_borrow_item_screen.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final Map customer;

  const CustomerDetailsScreen({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen>
    with SingleTickerProviderStateMixin {
  List items = [];
  List<Payment> payments = [];
  String? _currentUserName;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserProfile();
    loadItems();
    loadPayments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final name = await AuthService().getBestDisplayName();
    if (mounted) {
      setState(() {
        _currentUserName = name;
      });
    }
  }

  Future<void> loadItems() async {
    final data = await BorrowService().getBorrowItems(
      widget.customer['id'],
    );

    if (mounted) {
      setState(() {
        items = data;
      });
    }
  }

  // Computed live from items + payments, so it stays correct immediately
  // after an offline payment/edit even before the server's is_paid flag
  // has had a chance to sync.
  double get totalDebt {
    return items.fold<double>(0, (sum, item) => sum + double.parse(item['price'].toString()));
  }

  double get remainingDebt {
    double remaining = 0;
    for (var item in items) {
      final price = double.parse(item['price'].toString());
      final paidSoFar = _paidForItem(item['id']);
      final isPaid = item['is_paid'] == true || paidSoFar >= price;
      if (!isPaid) {
        final owed = price - paidSoFar;
        remaining += owed < 0 ? 0 : owed;
      }
    }
    return remaining;
  }

  Future<void> loadPayments() async {
    final data = await PaymentService().getPaymentsForCustomer(widget.customer['id']);
    if (mounted) {
      setState(() {
        payments = data;
      });
    }
  }

  double _paidForItem(String itemId) {
    return payments
        .where((p) => p.borrowItemId == itemId)
        .fold<double>(0, (sum, p) => sum + p.amount);
  }

  String formatCurrency(double amount) {
    if (amount == amount.toInt()) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  String formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];

      String day = date.day.toString().padLeft(2, '0');
      String month = months[date.month - 1];
      String year = date.year.toString();

      int hour = date.hour;
      String period = 'AM';
      if (hour >= 12) {
        period = 'PM';
        if (hour > 12) hour -= 12;
      }
      if (hour == 0) hour = 12;

      String minute = date.minute.toString().padLeft(2, '0');

      return "$day $month $year, $hour:$minute $period";
    } catch (e) {
      return dateStr;
    }
  }

  void _showEditDialog(Map item) {
    final nameController = TextEditingController(text: item['item_name']);
    final priceController = TextEditingController(text: formatCurrency(double.parse(item['price'].toString())));
    final reasonController = TextEditingController();
    final bool hasPayments = _paidForItem(item['id']) > 0;
    final finance = Theme.of(context).financeColors;

    showDialog(
      context: context,
      builder: (context) {
        String? reasonError;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Edit Item"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: "Item Name",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Price",
                    ),
                  ),
                  if (hasPayments) ...[
                    const SizedBox(height: 12),
                    Text(
                      "This item already has a payment recorded against it. "
                      "Please explain why it's being edited.",
                      style: TextStyle(fontSize: 12, color: finance.partial),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        labelText: "Reason (required)",
                        errorText: reasonError,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () async {
                    if (hasPayments && reasonController.text.trim().isEmpty) {
                      setDialogState(() => reasonError = "A reason is required");
                      return;
                    }

                    final nameToUse = await AuthService().getBestDisplayName();
                    final queuedOffline = await BorrowService().updateBorrowItem(
                      itemId: item['id'],
                      customerId: widget.customer['id'],
                      itemName: nameController.text,
                      price: double.parse(priceController.text),
                      oldItemName: item['item_name'],
                      oldPrice: double.parse(item['price'].toString()),
                      editedBy: nameToUse,
                      reason: hasPayments ? reasonController.text.trim() : null,
                    );

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    loadItems();
                    if (!mounted) return;
                    if (queuedOffline) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text("No internet — edit saved on this device and will sync automatically once you're back online."),
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteDialog(Map item, bool hasPayments) {
    final reasonController = TextEditingController();
    final finance = Theme.of(context).financeColors;
    final errorColor = Theme.of(context).colorScheme.error;

    showDialog(
      context: context,
      builder: (context) {
        String? reasonError;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Delete Item?"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Delete \"${item['item_name']}\" (${formatCurrency(double.parse(item['price'].toString()))} FCFA)?"),
                  if (hasPayments) ...[
                    const SizedBox(height: 12),
                    Text(
                      "This item already has a payment recorded against it. "
                      "The payment history stays on record either way, but please explain why the item is being deleted.",
                      style: TextStyle(fontSize: 12, color: finance.partial),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        labelText: "Reason (required)",
                        errorText: reasonError,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: errorColor),
                  onPressed: () async {
                    if (hasPayments && reasonController.text.trim().isEmpty) {
                      setDialogState(() => reasonError = "A reason is required");
                      return;
                    }

                    final nameToUse = await AuthService().getBestDisplayName();
                    final queuedOffline = await BorrowService().deleteBorrowItem(
                      item['id'],
                      customerId: widget.customer['id'],
                      changedBy: nameToUse,
                      reason: hasPayments ? reasonController.text.trim() : null,
                      itemName: item['item_name'],
                      price: double.parse(item['price'].toString()),
                    );

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    loadItems();
                    if (!mounted) return;
                    if (queuedOffline) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text("No internet — deletion saved on this device and will sync automatically once you're back online."),
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  },
                  child: const Text("Delete"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRecordPaymentDialog(Map item) {
    final price = double.parse(item['price'].toString());
    final paidSoFar = _paidForItem(item['id']);
    final remaining = (price - paidSoFar) < 0 ? 0.0 : (price - paidSoFar);

    final amountController = TextEditingController(text: formatCurrency(remaining));
    final noteController = TextEditingController();
    String selectedMethod = 'cash';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("Record Payment \u2014 ${item['item_name']}"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Balance: ${formatCurrency(remaining)} FCFA",
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Amount paid (FCFA)"),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedMethod,
                    decoration: const InputDecoration(labelText: "Method"),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'mobile_money', child: Text('Mobile Money')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) => setDialogState(() => selectedMethod = value ?? 'cash'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: "Note (optional)"),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(amountController.text);
                    if (amount == null || amount <= 0) return;

                    final nameToUse = await AuthService().getBestDisplayName();
                    final queuedOffline = await PaymentService().addPayment(
                      customerId: widget.customer['id'],
                      borrowItemId: item['id'],
                      amount: amount,
                      paidBy: nameToUse,
                      method: selectedMethod,
                      note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                      customerName: widget.customer['name'],
                      itemName: item['item_name'],
                    );

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    loadItems();
                    loadPayments();
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          queuedOffline
                              ? "No internet — payment saved on this device and will sync automatically once you're back online."
                              : "Payment recorded.",
                        ),
                        duration: Duration(seconds: queuedOffline ? 4 : 2),
                      ),
                    );
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPaymentTile(Payment payment) {
    // Look up the item name if this payment was tied to a specific borrow item
    String? itemName;
    final match = items.where((i) => i['id'] == payment.borrowItemId);
    if (match.isNotEmpty) {
      itemName = match.first['item_name'];
    }

    final finance = Theme.of(context).financeColors;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: finance.paid.withOpacity(0.14),
        child: Icon(Icons.payments_rounded, color: finance.paid, size: 20),
      ),
      title: Text(
        "${formatCurrency(payment.amount)} FCFA",
        style: moneyStyle(size: 16, color: finance.paid),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(itemName != null ? "For: $itemName" : "General payment (on account)"),
          Text(
            "By ${payment.paidBy} \u2022 ${payment.method}",
            style: const TextStyle(fontSize: 12),
          ),
          if (payment.note != null && payment.note!.isNotEmpty)
            Text(
              payment.note!,
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          Text(
            formatDate(payment.createdAt.toIso8601String()),
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finance = Theme.of(context).financeColors;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer['name'] ?? 'Customer Details'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: "Debts"),
            Tab(text: "Payments (${payments.length})"),
          ],
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Card(
            margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((widget.customer['location'] ?? '').toString().isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(widget.customer['location'], style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  if ((widget.customer['notes'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.customer['notes'],
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("TOTAL BORROWED", style: eyebrowStyle(scheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          AnimatedMoney(value: totalDebt, size: 16, color: scheme.onSurface),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("BALANCE OWED", style: eyebrowStyle(scheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          AnimatedMoney(
                            value: remainingDebt,
                            size: 24,
                            color: remainingDebt > 0 ? finance.overdue : finance.paid,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ReceiptTearDivider(color: scheme.outlineVariant, notchRadius: 4),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // --- Debts tab ---
                items.isEmpty
                    ? Center(
                        child: Text("No items borrowed yet", style: TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final double price = double.parse(item['price'].toString());
                          final double paidSoFar = _paidForItem(item['id']);
                          // Trust the local ledger over the server flag: if a
                          // payment was just recorded offline, is_paid won't be
                          // updated by the DB trigger until it syncs, but we
                          // already know the balance is covered.
                          final bool isPaid = item['is_paid'] == true || paidSoFar >= price;
                          final bool isPartiallyPaid = !isPaid && paidSoFar > 0;

                          final createdAt = DateTime.parse(item['created_at']);
                          final difference = DateTime.now().difference(createdAt).inDays;
                          final bool isOverdue = !isPaid && difference >= 7;

                          final accentColor = isPaid
                              ? finance.paid
                              : (isOverdue ? finance.overdue : (isPartiallyPaid ? finance.partial : scheme.primary));

                          return FadeInItem(
                            index: index,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardTheme.color,
                                borderRadius: BorderRadius.circular(14),
                                border: Border(left: BorderSide(color: accentColor, width: 4)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item['item_name'] ?? '',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          decoration: isPaid ? TextDecoration.lineThrough : null,
                                          color: isPaid ? scheme.onSurfaceVariant : scheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      "${formatCurrency(price)} FCFA",
                                      style: moneyStyle(size: 14, color: isPaid ? scheme.onSurfaceVariant : scheme.onSurface, weight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      "Added by ${item['added_by'] ?? 'Unknown'} \u2022 ${formatDate(item['created_at'])}",
                                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                                    ),
                                    if (isOverdue) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        "$difference days overdue",
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: finance.overdue),
                                      ),
                                    ],
                                    if (isPartiallyPaid) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        "Paid ${formatCurrency(paidSoFar)} of ${formatCurrency(price)} \u2014 ${formatCurrency(price - paidSoFar)} remaining",
                                        style: TextStyle(fontSize: 12, color: finance.partial, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                    if (isPaid) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        "Paid to ${item['paid_by'] ?? 'Unknown'} \u2022 ${formatDate(item['paid_at'])}",
                                        style: TextStyle(fontSize: 12, color: finance.paid, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: PopupMenuButton(
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      _showEditDialog(item);
                                    }
                                    if (value == 'delete') {
                                      _showDeleteDialog(item, paidSoFar > 0);
                                    }
                                    if (value == 'record_payment') {
                                      _showRecordPaymentDialog(item);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    if (!isPaid)
                                      PopupMenuItem(
                                        value: 'record_payment',
                                        child: Text(isPartiallyPaid ? 'Record Another Payment' : 'Record Payment'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                // --- Payment History tab ---
                payments.isEmpty
                    ? Center(
                        child: Text("No payments recorded yet", style: TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: payments.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) => _buildPaymentTile(payments[index]),
                      ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddBorrowItemScreen(
                customerId: widget.customer['id'],
                customerName: widget.customer['name'],
              ),
            ),
          );

          if (result == true || result == 'queued') {
            loadItems();
          }
          if (result == 'queued' && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("No internet — items saved on this device and will sync automatically once you're back online."),
                duration: Duration(seconds: 4),
              ),
            );
          }
        },
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
