import 'package:flutter/material.dart';

/// Brand palette for "Ledger & Indigo" — BorrowBook's design identity.
/// Named, deliberate hex values rather than default Material colors.
class BrandColors {
  BrandColors._();

  // Seed for Material 3's ColorScheme.fromSeed — deep indigo, evoking
  // indigo-dyed cloth rather than a generic fintech blue.
  static const indigo = Color(0xFF2E3F6E);

  // Warm ledger-paper background (light mode only).
  static const paper = Color(0xFFF3EEE1);
  static const paperDim = Color(0xFFE9E2CE);

  // Ink — near-black but warm, like real ink on paper rather than pure black.
  static const ink = Color(0xFF22252B);

  // "Night till" dark mode background — warm charcoal, not cold OLED-black.
  static const night = Color(0xFF1B1A17);
  static const nightSurface = Color(0xFF242320);

  // Semantic financial states — these carry meaning, so they stay
  // consistent across light and dark mode (same hue family, adjusted
  // lightness for contrast).
  static const paidLight = Color(0xFF2C6E49); // bill-green
  static const paidDark = Color(0xFF5FAE83);

  static const overdueLight = Color(0xFFA8412E); // rubber-stamp brick red
  static const overdueDark = Color(0xFFE28A79);

  static const partialLight = Color(0xFFB8862B); // ochre
  static const partialDark = Color(0xFFE0B15C);

  // Sync status is a technical state, not a money state, so it
  // deliberately lives in a different (cool, neutral) hue family from the
  // three above rather than reusing one of them.
  static const pendingSyncLight = Color(0xFF5B6B85);
  static const pendingSyncDark = Color(0xFF9AABC7);
}

/// Semantic colors accessible via Theme.of(context).extension<FinanceColors>()
/// so screens never hardcode a status color directly.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  final Color paid;
  final Color overdue;
  final Color partial;
  final Color pendingSync;

  const FinanceColors({
    required this.paid,
    required this.overdue,
    required this.partial,
    required this.pendingSync,
  });

  static const light = FinanceColors(
    paid: BrandColors.paidLight,
    overdue: BrandColors.overdueLight,
    partial: BrandColors.partialLight,
    pendingSync: BrandColors.pendingSyncLight,
  );

  static const dark = FinanceColors(
    paid: BrandColors.paidDark,
    overdue: BrandColors.overdueDark,
    partial: BrandColors.partialDark,
    pendingSync: BrandColors.pendingSyncDark,
  );

  @override
  FinanceColors copyWith({Color? paid, Color? overdue, Color? partial, Color? pendingSync}) {
    return FinanceColors(
      paid: paid ?? this.paid,
      overdue: overdue ?? this.overdue,
      partial: partial ?? this.partial,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    return FinanceColors(
      paid: Color.lerp(paid, other.paid, t)!,
      overdue: Color.lerp(overdue, other.overdue, t)!,
      partial: Color.lerp(partial, other.partial, t)!,
      pendingSync: Color.lerp(pendingSync, other.pendingSync, t)!,
    );
  }
}

/// Convenience accessor: Theme.of(context).financeColors
extension FinanceColorsExtension on ThemeData {
  FinanceColors get financeColors => extension<FinanceColors>() ?? FinanceColors.light;
}
