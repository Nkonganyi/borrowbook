import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Animates a money figure from its previous value to a new one whenever
/// it changes, instead of jumping instantly — makes recording a payment
/// feel like it actually did something to the ledger.
class AnimatedMoney extends StatelessWidget {
  final double value;
  final double size;
  final Color color;
  final String suffix;

  const AnimatedMoney({
    super.key,
    required this.value,
    required this.size,
    required this.color,
    this.suffix = ' FCFA',
  });

  String _format(double v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text(
          '${_format(animatedValue)}$suffix',
          style: moneyStyle(size: size, color: color),
        );
      },
    );
  }
}
