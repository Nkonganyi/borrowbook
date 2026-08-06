import 'package:flutter/material.dart';
import '../services/borrow_service.dart';
import '../services/auth_service.dart';
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
    }
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
    return Scaffold(
      appBar: AppBar(title: Text("Add Items for ${widget.customerName}")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _items[index].nameController,
                            decoration: const InputDecoration(labelText: "Item Name"),
                            onChanged: (_) => _addItemIfLastNotEmpty(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _items[index].priceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: "Price"),
                            onChanged: (_) => _addItemIfLastNotEmpty(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : saveItems,
                child: loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Save and Notify"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
