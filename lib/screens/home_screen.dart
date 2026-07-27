import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/customer_service.dart';
import '../services/dashboard_service.dart';
import '../services/borrow_service.dart';
import 'add_customer_screen.dart';
import 'customer_details_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List customers = [];
  Map<String, dynamic> stats = {};
  Map<String, int> overdueDaysMap = {}; // Maps customerId to overdue days
  String searchText = '';
  String userName = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadUser();
    loadData();
  }

  Future<void> loadData() async {
    await loadCustomers();
    await loadDashboard();
    // Trigger overdue detection and notifications
    BorrowService().checkAndNotifyOverdue();
  }

  Future<void> _loadUser() async {
    final name = await AuthService().getBestDisplayName();
    if (mounted) {
      setState(() {
        userName = name;
      });
    }
  }

  Future<void> loadDashboard() async {
    final result = await DashboardService().getStats();
    if (mounted) {
      setState(() {
        stats = result;
      });
    }
  }

  Future<void> loadCustomers() async {
    final customerData = await CustomerService().getCustomers();
    final unpaidItems = await BorrowService().getAllUnpaidItems();

    Map<String, int> overdueMap = {};
    final now = DateTime.now();

    for (var item in unpaidItems) {
      final createdAt = DateTime.parse(item['created_at']);
      final difference = now.difference(createdAt).inDays;

      if (difference >= 7) {
        final customerId = item['customer_id'];
        if (!overdueMap.containsKey(customerId) || difference > overdueMap[customerId]!) {
          overdueMap[customerId] = difference;
        }
      }
    }

    if (mounted) {
      setState(() {
        customers = customerData;
        overdueDaysMap = overdueMap;
      });
    }
  }

  Future<void> logout() async {
    await AuthService().logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showUpdateNameDialog() {
    final controller = TextEditingController(text: userName.contains('@') ? '' : userName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Set Your Name"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter your full name (e.g. Peter)",
            labelText: "Full Name",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              await AuthService().updateProfileName(controller.text.trim());
              if (!mounted) return;
              Navigator.pop(context);
              _loadUser();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  String formatCurrency(dynamic amount) {
    if (amount == null) return '0';
    double val = double.tryParse(amount.toString()) ?? 0;
    if (val == val.toInt()) return val.toInt().toString();
    return val.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Borrow Book"),
        actions: [
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(userName),
              accountEmail: Text(AuthService().currentUser?.email ?? ''),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Colors.blue),
              ),
              onDetailsPressed: _showUpdateNameDialog,
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text("Edit Display Name"),
              subtitle: const Text("Ensure your real name shows on debts"),
              onTap: () {
                Navigator.pop(context);
                _showUpdateNameDialog();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text("Logout"),
              onTap: logout,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(10),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Total Customers: ${stats['totalCustomers'] ?? 0}"),
                      Text("Owing: ${stats['customersOwing'] ?? 0}"),
                    ],
                  ),
                  const Divider(height: 20),
                  Text(
                    "Outstanding Debt: ${formatCurrency(stats['outstandingDebt'])} FCFA",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  if ((stats['overdueCustomers'] ?? 0) > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        "Overdue Customers: ${stats['overdueCustomers']}",
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search customer...",
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => searchText = value.toLowerCase()),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: customers.length,
              itemBuilder: (context, index) {
                final customer = customers[index];
                final customerId = customer['id'];
                final overdueDays = overdueDaysMap[customerId];
                final isOverdue = overdueDays != null;

                if (!customer['name'].toString().toLowerCase().contains(searchText)) {
                  return const SizedBox();
                }

                return ListTile(
                  title: Row(
                    children: [
                      Text(
                        customer['name'],
                        style: TextStyle(
                          color: isOverdue ? Colors.red : null,
                          fontWeight: isOverdue ? FontWeight.bold : null,
                        ),
                      ),
                      if (isOverdue) ...[
                        const SizedBox(width: 8),
                        Text(
                          "— OVERDUE ($overdueDays days)",
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ]
                    ],
                  ),
                  subtitle: Text(customer['location'] ?? 'No location'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer)),
                    );
                    loadData();
                  },
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
              builder: (_) => const AddCustomerScreen(),
            ),
          );
          if (result == true) {
            loadData();
          }
        },
      ),
    );
  }
}
