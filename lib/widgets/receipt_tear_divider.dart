import 'package:flutter/material.dart';

/// BorrowBook's one signature visual element: a row of small notches that
/// reads as a torn receipt edge. Used sparingly — under the balance
/// summary card is the main spot — never as generic decoration.
class ReceiptTearDivider extends StatelessWidget {
  final Color? color;
  final double notchRadius;

  const ReceiptTearDivider({super.key, this.color, this.notchRadius = 5});

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).colorScheme.outlineVariant;
    return SizedBox(
      height: notchRadius * 2 + 2,
      width: double.infinity,
      child: CustomPaint(
        painter: _TearPainter(color: resolvedColor, notchRadius: notchRadius),
      ),
    );
  }
}

class _TearPainter extends CustomPainter {
  final Color color;
  final double notchRadius;

  _TearPainter({required this.color, required this.notchRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final spacing = notchRadius * 2.6;
    final count = (size.width / spacing).floor();
    final startX = (size.width - (count * spacing)) / 2 + spacing / 2;

    for (int i = 0; i < count; i++) {
      final cx = startX + i * spacing;
      canvas.drawCircle(Offset(cx, 0), notchRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TearPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.notchRadius != notchRadius;
  }
}
