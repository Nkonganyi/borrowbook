import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/customer_service.dart';
import '../services/dashboard_service.dart';
import '../services/borrow_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/offline_banner.dart';
import '../widgets/animated_money.dart';
import '../widgets/receipt_tear_divider.dart';
import '../widgets/fade_in_item.dart';
import 'add_customer_screen.dart';
import 'customer_details_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum CustomerFilter { all, owing, overdue, paidOff }

class _HomeScreenState extends State<HomeScreen> {
  List customers = [];
  Map<String, dynamic> stats = {};
  Map<String, int> overdueDaysMap = {}; // Maps customerId to overdue days
  Set<String> owingCustomerIds = {}; // customerIds with at least one unpaid item
  String searchText = '';
  String userName = 'Loading...';
  CustomerFilter activeFilter = CustomerFilter.all;

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
    Set<String> owingIds = {};
    final now = DateTime.now();

    for (var item in unpaidItems) {
      final customerId = item['customer_id'];
      owingIds.add(customerId);

      final createdAt = DateTime.parse(item['created_at']);
      final difference = now.difference(createdAt).inDays;

      if (difference >= 7) {
        if (!overdueMap.containsKey(customerId) || difference > overdueMap[customerId]!) {
          overdueMap[customerId] = difference;
        }
      }
    }

    if (mounted) {
      setState(() {
        customers = customerData;
        overdueDaysMap = overdueMap;
        owingCustomerIds = owingIds;
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

  List get filteredCustomers {
    return customers.where((customer) {
      final customerId = customer['id'];
      final name = (customer['name'] ?? '').toString().toLowerCase();
      final phone = (customer['phone'] ?? '').toString().toLowerCase();
      final matchesSearch = searchText.isEmpty ||
          name.contains(searchText) ||
          phone.contains(searchText);

      if (!matchesSearch) return false;

      switch (activeFilter) {
        case CustomerFilter.owing:
          return owingCustomerIds.contains(customerId);
        case CustomerFilter.overdue:
          return overdueDaysMap.containsKey(customerId);
        case CustomerFilter.paidOff:
          return !owingCustomerIds.contains(customerId);
        case CustomerFilter.all:
          return true;
      }
    }).toList();
  }

  Widget _buildFilterChip(String label, CustomerFilter filter) {
    final isSelected = activeFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => activeFilter = filter),
      showCheckmark: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finance = Theme.of(context).financeColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Borrow Book"),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
            ),
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Dashboard',
          ),
          IconButton(onPressed: logout, icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: scheme.primary),
              accountName: Text(userName, style: const TextStyle(fontWeight: FontWeight.w700)),
              accountEmail: Text(AuthService().currentUser?.email ?? ''),
              currentAccountPicture: CircleAvatar(
                backgroundColor: scheme.onPrimary,
                child: Icon(Icons.person, size: 40, color: scheme.primary),
              ),
              onDetailsPressed: _showUpdateNameDialog,
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text("Edit Display Name"),
              subtitle: const Text("Ensure your real name shows on debts"),
              onTap: () {
                Navigator.pop(context);
                _showUpdateNameDialog();
              },
            ),
            ListenableBuilder(
              listenable: ThemeController.instance,
              builder: (context, _) {
                return SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text("Dark Mode"),
                  value: ThemeController.instance.isDark,
                  onChanged: (v) => ThemeController.instance.toggleDark(v),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text("Logout"),
              onTap: logout,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Card(
            margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("OUTSTANDING DEBT", style: eyebrowStyle(scheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          AnimatedMoney(
                            value: (double.tryParse(stats['outstandingDebt']?.toString() ?? '0') ?? 0),
                            size: 26,
                            color: scheme.onSurface,
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("${stats['totalCustomers'] ?? 0}", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: scheme.onSurface)),
                          Text("customers", style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatPill(
                        icon: Icons.people_outline,
                        label: "${stats['customersOwing'] ?? 0} owing",
                        color: finance.partial,
                      ),
                      if ((stats['overdueCustomers'] ?? 0) > 0)
                        _StatPill(
                          icon: Icons.warning_amber_rounded,
                          label: "${stats['overdueCustomers']} overdue",
                          color: finance.overdue,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: "Search by name or phone...",
              ),
              onChanged: (value) => setState(() => searchText = value.toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip("All", CustomerFilter.all),
                  const SizedBox(width: 8),
                  _buildFilterChip("Owing", CustomerFilter.owing),
                  const SizedBox(width: 8),
                  _buildFilterChip("Overdue", CustomerFilter.overdue),
                  const SizedBox(width: 8),
                  _buildFilterChip("Paid off", CustomerFilter.paidOff),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredCustomers.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        customers.isEmpty
                            ? "No customers yet. Tap + to add the first one."
                            : "No customers match this search or filter.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
                    itemCount: filteredCustomers.length,
                    itemBuilder: (context, index) {
                      final customer = filteredCustomers[index];
                      final customerId = customer['id'];
                      final overdueDays = overdueDaysMap[customerId];
                      final isOverdue = overdueDays != null;
                      final isOwing = owingCustomerIds.contains(customerId);

                      final accentColor = isOverdue
                          ? finance.overdue
                          : (isOwing ? finance.partial : finance.paid);

                      return FadeInItem(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: customer)),
                                );
                                loadData();
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border(left: BorderSide(color: accentColor, width: 4)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  customer['name'] ?? '',
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                                ),
                                              ),
                                              if (customer['_pendingSync'] == true) ...[
                                                const SizedBox(width: 6),
                                                Icon(Icons.sync_rounded, size: 14, color: finance.pendingSync),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            customer['location'] ?? 'No location',
                                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                                          ),
                                          if (isOverdue) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              "$overdueDays days overdue",
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: finance.overdue),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddCustomerScreen(),
            ),
          );
          if (result == true || result == 'queued') {
            loadData();
          }
          if (result == 'queued' && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("No internet — customer saved on this device and will sync automatically once you're back online."),
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

/// Small rounded pill used for the summary card's secondary stats.
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
