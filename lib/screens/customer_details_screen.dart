import 'package:flutter/material.dart';
import '../services/borrow_service.dart';
import '../services/auth_service.dart';
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

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  List items = [];
  double totalDebt = 0;
  double remainingDebt = 0;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    loadItems();
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

    double total = 0;
    double remaining = 0;

    for (var item in data) {
      total += double.parse(item['price'].toString());
      if (item['is_paid'] == false) {
        remaining += double.parse(item['price'].toString());
      }
    }

    setState(() {
      items = data;
      totalDebt = total;
      remainingDebt = remaining;
    });
  }

  Future<void> markPaid(Map item) async {
    final nameToUse = await AuthService().getBestDisplayName();

    await BorrowService().markAsPaid(
      item['id'],
      paidBy: nameToUse,
      itemName: item['item_name'],
      customerName: widget.customer['name'],
    );
    loadItems();
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

    showDialog(
      context: context,
      builder: (context) {
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
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Price",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final nameToUse = await AuthService().getBestDisplayName();
                await BorrowService().updateBorrowItem(
                  itemId: item['id'],
                  itemName: nameController.text,
                  price: double.parse(priceController.text),
                  oldItemName: item['item_name'],
                  oldPrice: double.parse(item['price'].toString()),
                  editedBy: nameToUse,
                );

                Navigator.pop(context);
                loadItems();
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer Details"),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Customer: ${widget.customer['name']}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text("Location: ${widget.customer['location'] ?? 'N/A'}"),
                  const SizedBox(height: 8),
                  Text("Notes: ${widget.customer['notes'] ?? 'No notes'}"),
                  const Divider(height: 24),
                  Text(
                    "Total Debt: ${formatCurrency(totalDebt)} FCFA",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Remaining: ${formatCurrency(remainingDebt)} FCFA",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final bool isPaid = item['is_paid'] == true;

                final createdAt = DateTime.parse(item['created_at']);
                final difference = DateTime.now().difference(createdAt).inDays;
                final bool isOverdue = !isPaid && difference >= 7;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "${item['item_name']} - ${formatCurrency(double.parse(item['price'].toString()))} FCFA",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: isPaid ? TextDecoration.lineThrough : null,
                            color: isPaid ? Colors.grey : (isOverdue ? Colors.red : null),
                          ),
                        ),
                      ),
                      if (isOverdue) ...[
                        const SizedBox(width: 8),
                        Text(
                          "— OVERDUE ($difference days)",
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ]
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        "Added by: ${item['added_by'] ?? 'Unknown'}",
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        formatDate(item['created_at']),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      if (isPaid) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Paid to: ${item['paid_by'] ?? 'Unknown'}",
                          style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formatDate(item['paid_at']),
                          style: const TextStyle(fontSize: 11, color: Colors.green),
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
                        await BorrowService().deleteBorrowItem(item['id']);
                        loadItems();
                      }
                      if (value == 'paid') {
                        await markPaid(item);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                      if (!isPaid)
                        const PopupMenuItem(
                          value: 'paid',
                          child: Text('Mark Paid'),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
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

          if (result == true) {
            loadItems();
          }
        },
      ),
    );
  }
}
