import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/dashboard_service.dart';
import '../widgets/offline_banner.dart';
import 'customer_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> stats = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DashboardService().getExtendedStats();
    if (mounted) {
      setState(() {
        stats = data;
        loading = false;
      });
    }
  }

  String _fmt(dynamic v) {
    final val = double.tryParse(v?.toString() ?? '0') ?? 0;
    if (val == val.toInt()) return val.toInt().toString();
    return val.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final weeklySeries = (stats['weeklySeries'] as List?) ?? [];
    final topDebtors = (stats['topDebtors'] as List?) ?? [];
    final aging = (stats['aging'] as List?) ?? [];

    double maxY = 100;
    for (final w in weeklySeries) {
      final borrowed = double.tryParse(w['borrowed'].toString()) ?? 0;
      final collected = double.tryParse(w['collected'].toString()) ?? 0;
      if (borrowed > maxY) maxY = borrowed;
      if (collected > maxY) maxY = collected;
    }
    maxY = maxY * 1.2;

    return Scaffold(
      appBar: AppBar(title: const Text("Dashboard")),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _buildStatsGrid(),
                        const SizedBox(height: 24),
                        _buildSectionTitle("Last 6 Weeks — Borrowed vs Collected"),
                        const SizedBox(height: 12),
                        _buildChart(weeklySeries, maxY),
                        const SizedBox(height: 8),
                        _buildLegend(),
                        const SizedBox(height: 24),
                        _buildSectionTitle("Top 5 Debtors"),
                        const SizedBox(height: 8),
                        if (topDebtors.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text("No outstanding balances \u2014 nice.", style: TextStyle(color: Colors.grey)),
                          )
                        else
                          ...topDebtors.map((d) => _buildDebtorTile(d, showDays: false)),
                        const SizedBox(height: 24),
                        _buildSectionTitle("Who To Chase First"),
                        const Padding(
                          padding: EdgeInsets.only(top: 2, bottom: 8),
                          child: Text(
                            "Ranked by balance \u00d7 days overdue \u2014 an old small debt can matter more than a big new one.",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        if (aging.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text("Nobody is overdue right now.", style: TextStyle(color: Colors.grey)),
                          )
                        else
                          ...aging.map((d) => _buildDebtorTile(d, showDays: true)),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        _statCard("Collected (Week)", "${_fmt(stats['collectedThisWeek'])} FCFA", Colors.green),
        _statCard("Collected (Month)", "${_fmt(stats['collectedThisMonth'])} FCFA", Colors.green.shade700),
        _statCard("Avg Days to Pay", _fmt(stats['avgDaysToPay']), Colors.blue),
        _statCard("Customers Overdue", "${_countOverdue()}", Colors.red),
      ],
    );
  }

  int _countOverdue() {
    final aging = (stats['aging'] as List?) ?? [];
    return aging.where((d) => (double.tryParse(d['daysOverdue'].toString()) ?? 0) >= 7).length;
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      color: color.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(List weeklySeries, double maxY) {
    if (weeklySeries.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text("No activity yet", style: TextStyle(color: Colors.grey))),
      );
    }

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= weeklySeries.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      weeklySeries[index]['label'].toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          barGroups: List.generate(weeklySeries.length, (i) {
            final week = weeklySeries[i];
            final borrowed = double.tryParse(week['borrowed'].toString()) ?? 0;
            final collected = double.tryParse(week['collected'].toString()) ?? 0;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(toY: borrowed, color: Colors.red.shade300, width: 8, borderRadius: BorderRadius.circular(2)),
                BarChartRodData(toY: collected, color: Colors.green.shade500, width: 8, borderRadius: BorderRadius.circular(2)),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendDot(Colors.red.shade300, "Borrowed"),
        const SizedBox(width: 20),
        _legendDot(Colors.green.shade500, "Collected"),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildDebtorTile(dynamic entry, {required bool showDays}) {
    final balance = double.tryParse(entry['balance'].toString()) ?? 0;
    final days = showDays ? (double.tryParse(entry['daysOverdue'].toString()) ?? 0).toInt() : null;
    final customer = entry['customer'] as Map?;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(entry['name']?.toString() ?? 'Unknown'),
        subtitle: days != null && days > 0
            ? Text("$days days since oldest unpaid item", style: const TextStyle(fontSize: 12))
            : null,
        trailing: Text(
          "${_fmt(balance)} FCFA",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: days != null && days >= 7 ? Colors.red : Colors.orange.shade800,
          ),
        ),
        onTap: customer == null
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerDetailsScreen(customer: Map<String, dynamic>.from(customer)),
                  ),
                );
              },
      ),
    );
  }
}
