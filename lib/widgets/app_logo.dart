import 'package:flutter/material.dart';

/// BorrowBook's mark: an open-book glyph in a rounded indigo tile, paired
/// with the wordmark. Used on the login/register screens and can be
/// dropped anywhere else branding is needed.
class AppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;

  const AppLogo({super.key, this.size = 56, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(Icons.menu_book_rounded, color: scheme.onPrimary, size: size * 0.56),
    );

    if (!showWordmark) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: 14),
        Text(
          "BorrowBook",
          style: TextStyle(
            fontSize: size * 0.34,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          "THE SHOP'S CREDIT LEDGER",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
