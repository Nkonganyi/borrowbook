import 'package:flutter/material.dart';
import '../services/borrow_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddBorrowItemScreen extends StatefulWidget {
  final String customerId;
  final String customerName;

  const AddBorrowItemScreen({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  @override
  State<AddBorrowItemScreen> createState() => _AddBorrowItemScreenState();
}

class _ItemEntry {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
}

class _AddBorrowItemScreenState extends State<AddBorrowItemScreen> {
  final List<_ItemEntry> _items = [_ItemEntry()];
  bool loading = false;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final name = await AuthService().getBestDisplayName();
    if (mounted) {
      setState(() {
        _currentUserName = name;
      });
    }
  }

  void _addItemIfLastNotEmpty() {
    final lastItem = _items.last;
    if (lastItem.nameController.text.trim().isNotEmpty &&
        lastItem.priceController.text.trim().isNotEmpty) {
      setState(() {
        _items.add(_ItemEntry());
      });
    } else {
      setState(() {}); // keep the running total live even without adding a row
    }
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      final removed = _items.removeAt(index);
      removed.nameController.dispose();
      removed.priceController.dispose();
    });
  }

  double get _runningTotal {
    double total = 0;
    for (var item in _items) {
      total += double.tryParse(item.priceController.text.trim()) ?? 0;
    }
    return total;
  }

  Future<void> saveItems() async {
    final validItems = _items.where((item) {
      return item.nameController.text.trim().isNotEmpty &&
          item.priceController.text.trim().isNotEmpty;
    }).toList();

    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter at least one item and price")),
      );
      return;
    }

    setState(() {
      loading = true;
    });

    // Refresh display name to be sure
    final nameToUse = await AuthService().getBestDisplayName();

    List<Map<String, dynamic>> itemsToInsert = [];
    final currentUser = Supabase.instance.client.auth.currentUser;

    try {
      for (var entry in validItems) {
        final priceText = entry.priceController.text.trim();
        final price = double.parse(priceText);
        itemsToInsert.add({
          'customer_id': widget.customerId,
          'item_name': entry.nameController.text.trim(),
          'price': price,
          'is_paid': false,
          'seller_email': currentUser?.email,
          'added_by': nameToUse,
        });
      }
    } catch (e) {
      setState(() {
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Prices must be valid numbers")),
      );
      return;
    }

    try {
      final queuedOffline = await BorrowService().addBorrowItems(
        itemsToInsert,
        customerName: widget.customerName,
        addedBy: nameToUse,
      );
      if (!mounted) return;
      Navigator.pop(context, queuedOffline ? 'queued' : true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (var item in _items) {
      item.nameController.dispose();
      item.priceController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text("Add Items \u2014 ${widget.customerName}")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          "${index + 1}",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _items[index].nameController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: "Item",
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (_) => _addItemIfLastNotEmpty(),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _items[index].priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            labelText: "Price",
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (_) => _addItemIfLastNotEmpty(),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 18, color: scheme.onSurfaceVariant),
                        onPressed: _items.length > 1 ? () => _removeItem(index) : null,
                        tooltip: 'Remove',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.4),
              border: Border(top: BorderSide(color: scheme.outlineVariant.withOpacity(0.4))),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("TOTAL", style: eyebrowStyle(scheme.onSurfaceVariant)),
                    Text(
                      "${_runningTotal == _runningTotal.toInt() ? _runningTotal.toInt() : _runningTotal} FCFA",
                      style: moneyStyle(size: 20, color: scheme.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: loading ? null : saveItems,
                    child: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Text("Save and Notify"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
