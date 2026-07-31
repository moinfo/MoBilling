import 'package:flutter/material.dart';

/// Semantic colours for the states a client actually sees, kept separate from
/// the Material scheme so status meaning never shifts when the seed colour or
/// brightness changes. Attached to [ThemeData] as an extension.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.settled,
    required this.pending,
    required this.attention,
    required this.overdue,
    required this.inactive,
    required this.onStatus,
  });

  /// Fully paid / active / accepted.
  final Color settled;

  /// Issued and awaiting action — sent, pending approval.
  final Color pending;

  /// Needs the client to act soon — partially paid, expiring.
  final Color attention;

  /// Past due, suspended, rejected.
  final Color overdue;

  /// Draft, cancelled, terminated — no longer actionable.
  final Color inactive;

  /// Foreground for text sitting on any of the above as a filled chip.
  final Color onStatus;

  static const light = StatusColors(
    settled: Color(0xFF2F9E44),
    pending: Color(0xFF1971C2),
    attention: Color(0xFFE8590C),
    overdue: Color(0xFFC92A2A),
    inactive: Color(0xFF868E96),
    onStatus: Colors.white,
  );

  static const dark = StatusColors(
    settled: Color(0xFF69DB7C),
    pending: Color(0xFF74C0FC),
    attention: Color(0xFFFFA94D),
    overdue: Color(0xFFFF8787),
    inactive: Color(0xFFADB5BD),
    onStatus: Color(0xFF111318),
  );

  /// Map a raw API status string onto a colour.
  ///
  /// Covers the `documents.status` enum — draft, pending_approval, sent,
  /// accepted, rejected, paid, overdue, partial, cancelled — plus the service
  /// and domain lifecycle words that share the same visual language. Unknown
  /// values fall back to [inactive] rather than throwing, because the enum has
  /// been extended by migration several times and will be again.
  Color forStatus(String? status) => switch (status?.toLowerCase().trim()) {
        'paid' || 'accepted' || 'active' || 'completed' || 'resolved' =>
          settled,
        'sent' || 'pending_approval' || 'pending' || 'open' || 'processing' =>
          pending,
        'partial' || 'expiring' || 'grace' || 'awaiting_payment' => attention,
        'overdue' || 'rejected' || 'suspended' || 'failed' || 'expired' =>
          overdue,
        _ => inactive,
      };

  /// Human label for a raw status: `pending_approval` -> `Pending approval`.
  static String label(String? status) {
    if (status == null || status.isEmpty) return 'Unknown';
    final words = status.replaceAll('_', ' ').trim();
    return words[0].toUpperCase() + words.substring(1);
  }

  @override
  StatusColors copyWith({
    Color? settled,
    Color? pending,
    Color? attention,
    Color? overdue,
    Color? inactive,
    Color? onStatus,
  }) =>
      StatusColors(
        settled: settled ?? this.settled,
        pending: pending ?? this.pending,
        attention: attention ?? this.attention,
        overdue: overdue ?? this.overdue,
        inactive: inactive ?? this.inactive,
        onStatus: onStatus ?? this.onStatus,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      settled: Color.lerp(settled, other.settled, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      overdue: Color.lerp(overdue, other.overdue, t)!,
      inactive: Color.lerp(inactive, other.inactive, t)!,
      onStatus: Color.lerp(onStatus, other.onStatus, t)!,
    );
  }
}

/// Spacing scale. A single source beats scattered magic numbers when two
/// people build screens against the same design.
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
}

/// App theming.
///
/// Seeded from Mantine's default blue so the mobile app reads as the same
/// product as the web portal, which uses Mantine's stock palette.
abstract final class AppTheme {
  static const Color seed = Color(0xFF228BE6);

  static ThemeData light() => _build(Brightness.light, StatusColors.light);
  static ThemeData dark() => _build(Brightness.dark, StatusColors.dark);

  static ThemeData _build(Brightness brightness, StatusColors status) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      extensions: [status],
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.md,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
    );
  }
}

/// Convenience access to the status palette from any build context.
extension StatusColorsContext on BuildContext {
  StatusColors get statusColors =>
      Theme.of(this).extension<StatusColors>() ?? StatusColors.light;
}
