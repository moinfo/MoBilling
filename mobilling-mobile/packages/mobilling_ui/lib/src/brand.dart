import 'package:flutter/material.dart';

import 'theme.dart';

/// Brand surfaces shared by the screens that carry the company's identity
/// (sign-in, splash, the offline gate) rather than its data.
///
/// These mirror the web design handoff
/// (`design_handoff_mobilling/README.md` §2.1): an ink panel with a blue and
/// a green radial glow, a 4px rule in the four logo colours pinned to its top
/// edge, and Plex Mono eyebrows. The ink is the same in light and dark
/// themes — it is the brand's ground, not the app's.

/// The four logo hues as one gradient, in the order the logo draws them:
/// gold → green → blue → orange.
const brandGradient = LinearGradient(
  colors: [
    Color(0xFFF5C518),
    Color(0xFF2FAE60),
    Color(0xFF1A68B0),
    Color(0xFFF0632C),
  ],
  stops: [0, 0.38, 0.68, 1],
);

/// The 4px full-bleed brand rule.
class BrandRule extends StatelessWidget {
  const BrandRule({super.key, this.height = 4});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: const BoxDecoration(gradient: brandGradient),
  );
}

/// Ink ground with the two radial glows, the brand rule on its top edge, and
/// room for content. Always dark — see the library note above.
class InkPanel extends StatelessWidget {
  const InkPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.lg),
    this.borderRadius = BorderRadius.zero,
    this.rule = true,
    this.blueGlow = true,
    this.greenGlow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// Off for a panel that continues an ink surface above it (the dashboard's
  /// money panel under the masthead): the rule marks the top of the screen,
  /// and there is only one of those.
  final bool rule;

  /// The two glows can be split between two stacked panels so they read as
  /// one surface: blue top-right on the upper, green bottom-left on the lower.
  final bool blueGlow;
  final bool greenGlow;

  /// The handoff's ink: a touch bluer and deeper than [Brand.ink] so white
  /// type and the gold eyebrow sit on it with the same contrast as the web.
  static const ground = Color(0xFF0C1220);

  /// Text colours that sit on [ground], from the handoff: body copy, the
  /// utility strip's muted grey, and the gold used for eyebrows and marks.
  static const bodyText = Color(0xFFB3BDCB);
  static const mutedText = Color(0xFF9AA6B6);
  static const gold = Color(0xFFFFD24A);

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius,
    child: ColoredBox(
      color: ground,
      child: Stack(
        children: [
          // Blue glow, top-right; green glow, bottom-left. Soft enough to
          // read as light on the panel rather than as shapes.
          if (blueGlow)
            const Positioned(
              top: -180,
              right: -140,
              child: _Glow(size: 560, color: Color(0xFF1A68B0), opacity: 0.55),
            ),
          if (greenGlow)
            const Positioned(
              bottom: -220,
              left: -160,
              child: _Glow(size: 520, color: Color(0xFF2FAE60), opacity: 0.32),
            ),
          if (rule)
            const Positioned(top: 0, left: 0, right: 0, child: BrandRule()),
          Padding(padding: padding, child: child),
        ],
      ),
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color, required this.opacity});

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.68],
        ),
      ),
    ),
  );
}

/// A Plex Mono eyebrow in a translucent pill with a coloured dot — the
/// handoff's `BUILT FOR EAST AFRICA` badge. Text is upper-cased here so
/// callers pass plain words.
class EyebrowPill extends StatelessWidget {
  const EyebrowPill(
    this.text, {
    super.key,
    this.dotColor = const Color(0xFF2FAE60),
    this.textColor = const Color(0xFFFFD24A),
    this.onInk = true,
  });

  final String text;
  final Color dotColor;
  final Color textColor;

  /// On the ink panel the pill is translucent white; on a light surface it
  /// borrows the theme's container colours instead.
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
      decoration: BoxDecoration(
        color: onInk
            ? Colors.white.withValues(alpha: 0.08)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: onInk
              ? Colors.white.withValues(alpha: 0.16)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            style: Type.mono(
              11.5,
              color: onInk ? textColor : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The wordmark: logo mark beside "MoBilling" in the display face.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 34, this.onInk = false});

  final double size;
  final bool onInk;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/moinfotech-logo.png',
        package: 'mobilling_ui',
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Moinfotech',
      ),
      const SizedBox(width: 10),
      Text(
        'MoBilling',
        style: Type.display(
          size * 0.6,
          color: onInk ? Colors.white : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ],
  );
}

/// Fade-and-rise entrance, staggered by [delay]. Collapses to an instant
/// show when the platform asks for reduced motion — the layout is the same
/// either way, so nothing depends on the animation having run.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 700),
    this.offset = 22,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    // The handoff's cubic-bezier(0.22, 0.72, 0.2, 1): fast out, long settle.
    curve: const Cubic(0.22, 0.72, 0.2, 1),
  );
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    builder: (context, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(
        offset: Offset(0, widget.offset * (1 - _curve.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}
