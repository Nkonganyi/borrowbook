import 'package:flutter/material.dart';

/// Breakpoints tuned for "does a two-pane master-detail layout make sense
/// here" — a phone in portrait never crosses this, a tablet (or a phone in
/// landscape, or a folded/desktop window) does.
class Responsive {
  Responsive._();

  static const double tabletBreakpoint = 700;
  static const double formMaxWidth = 480;

  static bool isWide(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= tabletBreakpoint;
  }
}

/// Centers content and caps its width on wide screens, so a form doesn't
/// stretch edge-to-edge on a tablet. On narrow screens it's a no-op.
class ResponsiveFormWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveFormWidth({super.key, required this.child, this.maxWidth = Responsive.formMaxWidth});

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isWide(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
