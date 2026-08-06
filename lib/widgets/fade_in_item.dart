import 'package:flutter/material.dart';

/// Wraps a list row so it fades and slides up into place, staggered by
/// its index. Used on the two main lists (customers, ledger items) so the
/// screen feels like it's settling into place rather than just appearing.
class FadeInItem extends StatelessWidget {
  final int index;
  final Widget child;

  const FadeInItem({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final delay = (index * 40).clamp(0, 400);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
