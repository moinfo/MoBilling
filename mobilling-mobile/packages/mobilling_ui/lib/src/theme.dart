import 'package:flutter/material.dart';

/// The Moinfotech palette, read off the company mark.
///
/// The logo is a network graph: a gold node, a green node and a blue node
/// joined by gradient strokes, with an orange descender. Those four hues are
/// the whole palette — no seed generator, no invented accents.
///
/// The useful accident is that the three node colours are already this
/// product's story. Green → gold → orange is exactly the aging ramp the
/// business runs on (current → due soon → overdue), so colour in this app
/// only ever answers one question: **how healthy is this money?** A hue is
/// never spent on decoration, because every hue is already spoken for.
abstract final class Brand {
  /// Logo blue, taken down to an ink. Text, and the dark shell's ground.
  static const ink = Color(0xFF10243A);

  /// The blue node. Actions and links — never money.
  static const signal = Color(0xFF1D6FB8);

  /// The green node. Paid, collected, verified, healthy.
  static const settled = Color(0xFF17A672);

  /// The gold node. Due soon, pending, awaiting someone.
  static const warn = Color(0xFFF2A93B);

  /// The orange descender. Overdue, failed, short.
  static const overdue = Color(0xFFE4572E);

  /// A cool off-white. Deliberately not cream: this app is read in equatorial
  /// daylight, where a warm ground turns muddy behind glare.
  static const paper = Color(0xFFF7F8FA);

  /// Ground for the dark shell — the ink, lifted just off black so elevation
  /// still reads.
  static const inkDeep = Color(0xFF0A1826);
}

/// Semantic colours for the states a person actually sees.
///
/// Attached as a [ThemeExtension] so status meaning survives a change of
/// brightness or primary colour.
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

  /// Fully paid, active, verified.
  final Color settled;

  /// Issued and waiting on someone else.
  final Color pending;

  /// Needs action soon — partially paid, expiring, awaiting approval.
  final Color attention;

  /// Past due, suspended, rejected, short.
  final Color overdue;

  /// Draft, cancelled, terminated — no longer in play.
  final Color inactive;

  /// Foreground for text on a filled status colour.
  final Color onStatus;

  static const light = StatusColors(
    settled: Brand.settled,
    pending: Brand.signal,
    attention: Brand.warn,
    overdue: Brand.overdue,
    inactive: Color(0xFF7A8798),
    onStatus: Colors.white,
  );

  /// Lifted for dark ground. The hues hold their identity; only luminance
  /// moves, so "green means paid" survives the theme switch.
  static const dark = StatusColors(
    settled: Color(0xFF3ECF9A),
    pending: Color(0xFF5FA8E8),
    attention: Color(0xFFFFC266),
    overdue: Color(0xFFFF8A66),
    inactive: Color(0xFF8E9CAD),
    onStatus: Brand.inkDeep,
  );

  /// The aging ramp, oldest last. Used by the collection ageing bar and any
  /// other by-age breakdown, so the same five steps always mean the same five
  /// ages.
  List<Color> get agingRamp => [settled, pending, attention, overdue, overdue];

  /// Map a raw API status onto a colour.
  ///
  /// Unknown values fall back to [inactive] rather than throwing — the
  /// `documents.status` enum has been extended by migration several times and
  /// will be again.
  Color forStatus(String? status) => switch (status?.toLowerCase().trim()) {
        'paid' ||
        'accepted' ||
        'active' ||
        'completed' ||
        'resolved' ||
        // HR + operations (Aug 2026): a decided/locked/linked state.
        'approved' ||
        'finalized' ||
        'imported' ||
        'recovered' ||
        'paid_off' =>
          settled,
        'sent' || 'pending_approval' || 'pending' || 'open' || 'processing' =>
          pending,
        'partial' ||
        'expiring' ||
        'grace' ||
        'awaiting_payment' ||
        'not_imported' =>
          attention,
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

/// Spacing scale. One source beats magic numbers when several people build
/// screens against the same design.
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
  static const double lg = 20;
  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
}

/// Type tokens.
///
/// The app carries no bundled display face, so personality has to come from
/// scale, weight and tracking rather than a novelty typeface — and from
/// **tabular figures**, which is the one typographic decision that is also a
/// functional one here. Proportional digits make a column of money jitter as
/// values change and refuse to align; `tnum` fixes both, and this is an app
/// whose entire content is columns of money.
///
/// [family] is the single override point: drop a licensed face into the
/// package, set it here, and every surface picks it up.
abstract final class Type {
  static const String? family = null;

  /// Lining, fixed-width digits. Every monetary or countable figure uses this.
  static const figures = <FontFeature>[
    FontFeature.tabularFigures(),
    FontFeature.liningFigures(),
  ];

  /// Small, wide-tracked, upper-case. Reserved for labels that name a figure —
  /// never for content, which would make the interface shout.
  static const double eyebrowTracking = 0.8;
}

/// App theming.
///
/// Built from an explicit [ColorScheme] rather than `fromSeed`: seeding tints
/// every neutral toward the primary, which is how a Material app announces
/// itself as a Material app. Pinning the neutrals keeps surfaces genuinely
/// neutral so the four brand hues are the only colour in the room.
abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Brand.signal,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCEAF7),
      onPrimaryContainer: Color(0xFF0B3A5E),
      secondary: Brand.settled,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD6F2E6),
      onSecondaryContainer: Color(0xFF063D2C),
      error: Brand.overdue,
      onError: Colors.white,
      errorContainer: Color(0xFFFBE3DB),
      onErrorContainer: Color(0xFF6B1F0B),
      surface: Brand.paper,
      onSurface: Brand.ink,
      onSurfaceVariant: Color(0xFF5A6875),
      outline: Color(0xFFC3CCD6),
      outlineVariant: Color(0xFFE2E7EC),
      surfaceContainerHighest: Color(0xFFECEFF3),
    );

    return _build(scheme, StatusColors.light, Colors.white);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF5FA8E8),
      onPrimary: Brand.inkDeep,
      primaryContainer: Color(0xFF16456F),
      onPrimaryContainer: Color(0xFFD5E8F8),
      secondary: Color(0xFF3ECF9A),
      onSecondary: Brand.inkDeep,
      secondaryContainer: Color(0xFF0E5540),
      onSecondaryContainer: Color(0xFFD2F5E7),
      error: Color(0xFFFF8A66),
      onError: Brand.inkDeep,
      errorContainer: Color(0xFF6B2413),
      onErrorContainer: Color(0xFFFFDBD0),
      surface: Brand.inkDeep,
      onSurface: Color(0xFFE6ECF2),
      onSurfaceVariant: Color(0xFF9BAAB9),
      outline: Color(0xFF3A4B5C),
      outlineVariant: Color(0xFF1E3145),
      surfaceContainerHighest: Color(0xFF16293C),
    );

    return _build(scheme, StatusColors.dark, const Color(0xFF122436));
  }

  static ThemeData _build(
    ColorScheme scheme,
    StatusColors status,
    Color cardColor,
  ) {
    final text = _textTheme(scheme);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: Type.family,
      extensions: [status],
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // A hairline instead of a shadow: this app is dense lists, and a
        // shadow under every app bar reads as clutter at scale.
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        titleTextStyle: text.titleMedium,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: _inputBorder(scheme.outlineVariant),
        enabledBorder: _inputBorder(scheme.outlineVariant),
        focusedBorder: _inputBorder(scheme.primary, width: 2),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.md,
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Height only. `Size.fromHeight` is `Size(infinity, 52)`, which
          // forces *every* button full-width — wrong for an inline
          // action, and an assert in any unbounded parent. Screens that
          // want a full-width button stretch it themselves.
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // Height only. `Size.fromHeight` is `Size(infinity, 52)`, which
          // forces *every* button full-width — wrong for an inline
          // action, and an assert in any unbounded parent. Screens that
          // want a full-width button stretch it themselves.
          minimumSize: const Size(64, 52),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge),
      ),

      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        labelStyle: text.labelSmall,
      ),

      listTileTheme: ListTileThemeData(
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
        surfaceTintColor: Colors.transparent,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Brand.ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.outlineVariant,
        linearMinHeight: 6,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: color, width: width),
      );

  /// A deliberate scale rather than Material's defaults.
  ///
  /// Headline and title sizes are tightened (negative tracking) so large
  /// figures read as one object; labels are widened and upper-cased so a
  /// caption never competes with the number it names.
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = ThemeData(brightness: scheme.brightness).textTheme;

    return base.copyWith(
      // Reserved for the money readout and hero figures.
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 40,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        fontFeatures: Type.figures,
        color: scheme.onSurface,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 30,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        fontFeatures: Type.figures,
        color: scheme.onSurface,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: scheme.onSurface,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.35),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.4),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.35),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        fontFeatures: Type.figures,
      ),
      // The eyebrow: names a figure without competing with it.
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: Type.eyebrowTracking,
      ),
    );
  }
}

/// Reach the status palette from any build context.
extension StatusColorsContext on BuildContext {
  StatusColors get statusColors =>
      Theme.of(this).extension<StatusColors>() ?? StatusColors.light;
}
