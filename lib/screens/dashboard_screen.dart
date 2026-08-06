import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/dashboard_service.dart';
import '../theme/app_theme.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final finance = Theme.of(context).financeColors;

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
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildStatsGrid(finance, scheme),
                        const SizedBox(height: 28),
                        _buildSectionTitle("LAST 6 WEEKS \u2014 BORROWED VS COLLECTED", scheme),
                        const SizedBox(height: 14),
                        _buildChart(weeklySeries, maxY, finance),
                        const SizedBox(height: 10),
                        _buildLegend(finance),
                        const SizedBox(height: 28),
                        _buildSectionTitle("TOP 5 DEBTORS", scheme),
                        const SizedBox(height: 8),
                        if (topDebtors.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text("No outstanding balances \u2014 nice.", style: TextStyle(color: scheme.onSurfaceVariant)),
                          )
                        else
                          ...topDebtors.map((d) => _buildDebtorTile(d, showDays: false, finance: finance, scheme: scheme, context: context)),
                        const SizedBox(height: 28),
                        _buildSectionTitle("WHO TO CHASE FIRST", scheme),
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(
                            "Ranked by balance \u00d7 days overdue \u2014 an old small debt can matter more than a big new one.",
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ),
                        if (aging.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text("Nobody is overdue right now.", style: TextStyle(color: scheme.onSurfaceVariant)),
                          )
                        else
                          ...aging.map((d) => _buildDebtorTile(d, showDays: true, finance: finance, scheme: scheme, context: context)),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme scheme) {
    return Text(title, style: eyebrowStyle(scheme.onSurfaceVariant));
  }

  Widget _buildStatsGrid(FinanceColors finance, ColorScheme scheme) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        _statCard("Collected (Week)", "${_fmt(stats['collectedThisWeek'])} FCFA", finance.paid),
        _statCard("Collected (Month)", "${_fmt(stats['collectedThisMonth'])} FCFA", finance.paid),
        _statCard("Avg Days to Pay", _fmt(stats['avgDaysToPay']), scheme.primary),
        _statCard("Customers Overdue", "${_countOverdue()}", finance.overdue),
      ],
    );
  }

  int _countOverdue() {
    final aging = (stats['aging'] as List?) ?? [];
    return aging.where((d) => (double.tryParse(d['daysOverdue'].toString()) ?? 0) >= 7).length;
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: eyebrowStyle(color.withValues(alpha: 0.85))),
            const SizedBox(height: 8),
            Text(value, style: moneyStyle(size: 18, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(List weeklySeries, double maxY, FinanceColors finance) {
    if (weeklySeries.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text("No activity yet")),
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
                  final index = value.round();
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
                BarChartRodData(toY: borrowed, color: finance.overdue, width: 8, borderRadius: BorderRadius.circular(2)),
                BarChartRodData(toY: collected, color: finance.paid, width: 8, borderRadius: BorderRadius.circular(2)),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildLegend(FinanceColors finance) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendDot(finance.overdue, "Borrowed"),
        const SizedBox(width: 20),
        _legendDot(finance.paid, "Collected"),
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

  Widget _buildDebtorTile(
    dynamic entry, {
    required bool showDays,
    required FinanceColors finance,
    required ColorScheme scheme,
    required BuildContext context,
  }) {
    final balance = double.tryParse(entry['balance'].toString()) ?? 0;
    final days = showDays ? (double.tryParse(entry['daysOverdue'].toString()) ?? 0).toInt() : null;
    final customer = entry['customer'] as Map?;

    final amountColor = days != null && days >= 7 ? finance.overdue : finance.partial;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: amountColor, width: 4)),
      ),
      child: ListTile(
        title: Text(entry['name']?.toString() ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: days != null && days > 0
            ? Text("$days days since oldest unpaid item", style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
            : null,
        trailing: Text("${_fmt(balance)} FCFA", style: moneyStyle(size: 14, color: amountColor)),
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
