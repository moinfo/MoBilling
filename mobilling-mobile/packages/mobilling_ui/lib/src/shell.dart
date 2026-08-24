import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'theme.dart';

/// The chrome every signed-in screen sits between: an ink masthead at the top
/// and the tab bar at the bottom.
///
/// The masthead is the sign-in screen's ink panel folded down to one line —
/// same ground, same glow, same brand rule on the screen's top edge — so the
/// identity that greets people at the door follows them into the app. The
/// tab bar is deliberately the quiet half: paper, a hairline, and a sliver of
/// signal blue for the active tab. Two dark bands would crush the content
/// between them.
///
/// Both are shared by the staff and client shells so the two audiences are
/// recognisably looking at the same product.

/// The ink masthead. Implements [PreferredSizeWidget] so it drops into
/// `Scaffold.appBar`; it lays out the status-bar inset itself.
///
/// Hierarchy is the sign-in screen's: a Plex Mono eyebrow naming the context
/// (the tenant) *above* the Archivo title naming the screen. Where a scaffold
/// has a drawer the menu button appears on its own; [trailing] is the place
/// for the account tile.
class ShellTopBar extends StatelessWidget implements PreferredSizeWidget {
  const ShellTopBar({
    super.key,
    required this.title,
    this.eyebrow,
    this.leading,
    this.trailing,
    this.edge = true,
    this.bottom,
  });

  final String title;

  /// Tabs (an [InkTabBar]) or a search field rendered on the ink under the
  /// title row — the masthead's answer to `AppBar.bottom`.
  final PreferredSizeWidget? bottom;

  /// Drop the bottom hairline when the screen continues the ink beneath the
  /// masthead (the dashboard's money panel), so the two read as one surface.
  final bool edge;

  /// Upper-cased here; pass plain words.
  final String? eyebrow;

  /// Defaults to a menu button when the enclosing scaffold has a drawer.
  final Widget? leading;
  final Widget? trailing;

  /// Height below the status bar.
  static const double height = 66;

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final scaffold = Scaffold.maybeOf(context);
    final route = ModalRoute.of(context);
    final Widget? lead;
    if (leading != null) {
      lead = leading;
    } else if (scaffold?.hasDrawer ?? false) {
      lead = InkActionButton(
        icon: Icons.menu_rounded,
        tooltip: 'Menu',
        onPressed: scaffold!.openDrawer,
      );
    } else if (route?.canPop ?? false) {
      // A pushed screen: the way back, in the same tile as the menu.
      lead = InkActionButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      );
    } else {
      lead = null;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status icons on the ink, whatever the app's theme is.
      value: SystemUiOverlayStyle.light,
      child: InkPanel(
        padding: EdgeInsets.fromLTRB(0, top, 0, 0),
        child: Container(
          // In the dark theme the scaffold is almost the same ink, so the
          // masthead needs an edge of its own; on paper it is invisible.
          decoration: BoxDecoration(
            border: Border(
              bottom: edge
                  ? BorderSide(color: Colors.white.withValues(alpha: 0.10))
                  : BorderSide.none,
            ),
          ),
          // The title row takes whatever is left after the bottom slot
          // rather than a fixed height: the scaffold's budget for an app bar
          // can land a fraction of a pixel under the sum of the two, and a
          // Column of two fixed heights would overflow by that fraction.
          child: Column(
            children: [
              Expanded(child: _titleRow(lead)),
              if (bottom != null) bottom!,
            ],
          ),
        ),
      ),
    );
  }

  Widget _titleRow(Widget? lead) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
    child: Row(
      children: [
        if (lead != null) ...[lead, const SizedBox(width: Spacing.md - 2)],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null && eyebrow!.isNotEmpty) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.mono(
                    10.5,
                    tracking: 0.08,
                    color: InkPanel.mutedText,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.display(22, color: Colors.white),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: Spacing.sm), trailing!],
      ],
    ),
  );
}

/// Tabs on the ink, for [ShellTopBar.bottom]: Plex Mono upper-case labels,
/// the active one in white with the same signal-blue sliver as the bottom
/// bar. Pass plain words; they are upper-cased here.
class InkTabBar extends StatelessWidget implements PreferredSizeWidget {
  const InkTabBar({
    super.key,
    required this.tabs,
    this.controller,
    this.onTap,
    this.isScrollable = false,
  });

  final List<String> tabs;
  final TabController? controller;
  final ValueChanged<int>? onTap;
  final bool isScrollable;

  static const double height = 44;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: TabBar(
        controller: controller,
        onTap: onTap,
        isScrollable: isScrollable,
        tabAlignment: isScrollable ? TabAlignment.start : TabAlignment.fill,
        padding: isScrollable
            ? const EdgeInsets.symmetric(horizontal: Spacing.sm)
            : EdgeInsets.zero,
        labelColor: Colors.white,
        unselectedLabelColor: InkPanel.mutedText,
        labelStyle: Type.mono(10.5, tracking: 0.08),
        unselectedLabelStyle: Type.mono(10.5, tracking: 0.08),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: 3, color: scheme.primary),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(
          Colors.white.withValues(alpha: 0.06),
        ),
        splashFactory: InkRipple.splashFactory,
        tabs: [
          for (final t in tabs) Tab(text: t.toUpperCase(), height: height),
        ],
      ),
    );
  }
}

/// A search field on the ink, for [ShellTopBar.bottom].
///
/// Translucent white on the masthead's ground, the same recipe as
/// [InkActionButton]. The prefix icon carries explicit constraints because
/// Material otherwise forces a 48px minimum on it, which overflows a field
/// sized to sit under a title row.
class InkSearchField extends StatelessWidget implements PreferredSizeWidget {
  const InkSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  /// Shows a clear button once there is something to clear. Without it a
  /// search can only be undone by selecting the text and deleting it.
  final VoidCallback? onClear;

  /// Total height, including the gap under the field.
  static const double height = 60;
  static const double _field = 46;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(double alpha) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: alpha)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        0,
        Spacing.md,
        height - _field,
      ),
      child: SizedBox(
        height: _field,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: InkPanel.mutedText),
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: InkPanel.mutedText,
              ),
              // Without this Material reserves 48px for the icon and the field
              // overflows its own box by a pixel.
              prefixIconConstraints: const BoxConstraints(
                minWidth: 42,
                minHeight: 0,
              ),
              suffixIcon: (onClear == null || value.text.isEmpty)
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: InkPanel.mutedText,
                      tooltip: 'Clear search',
                      onPressed: onClear,
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 0,
              ),
              isDense: true,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.10),
              contentPadding: const EdgeInsets.fromLTRB(0, 12, 15, 12),
              border: border(0.16),
              enabledBorder: border(0.16),
              focusedBorder: border(0.45),
            ),
          ),
        ),
      ),
    );
  }
}

/// The label above a form field, as the sign-in screen sets it.
///
/// A form's labels sit above their controls rather than floating inside
/// them: a floating label moves when the field fills, which makes a column
/// of fields twitch as it is completed.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);
}

/// Full-width primary action on the handoff's blue gradient, with its soft
/// blue shadow. One per screen: it is the thing the screen exists to let
/// you do. A spinner replaces the leading space while busy so the label
/// keeps its place.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.75,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A68B0), Color(0xFF12507F)],
            ),
            borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A68B0).withValues(alpha: 0.9),
                blurRadius: 30,
                offset: const Offset(0, 16),
                spreadRadius: -18,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: onPressed,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                    ] else if (icon != null) ...[
                      Icon(icon, size: 18, color: Colors.white),
                      const SizedBox(width: Spacing.sm),
                    ],
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The handoff's 38×38 radius-11 utility button, on ink: translucent white
/// with a translucent hairline, the same recipe as [EyebrowPill].
class InkActionButton extends StatelessWidget {
  const InkActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    ),
  );
}

/// The account tile: the signed-in person's initial, gold on ink, in the
/// handoff's rounded avatar square. Tapping it is where account actions live
/// — a sign-out icon has no business sitting one thumb away on every screen.
class InkAvatar extends StatelessWidget {
  const InkAvatar({
    super.key,
    required this.name,
    required this.onTap,
    this.tooltip = 'Account',
  });

  final String name;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: '$tooltip: $name',
        child: Material(
          color: Colors.white.withValues(alpha: 0.10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Center(
                child: Text(
                  initial,
                  style: Type.display(16, weight: 700, color: InkPanel.gold),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One destination on the [ShellNavBar].
class ShellNavItem {
  const ShellNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget icon;
  final Widget selectedIcon;

  /// Upper-cased by the bar; pass plain words, and keep them to one.
  final String label;
}

/// The bottom tab bar.
///
/// Paper ground, a hairline on top, and the active tab marked by a 3px
/// signal-blue sliver on that top edge — the same instrument as the brand
/// rule, in the colour this app reserves for actions. The sliver slides
/// between tabs rather than appearing, so a switch reads as movement along
/// a row, not as two unrelated highlights.
///
/// Labels are Plex Mono upper-case: the one register this app allows for a
/// word that *names* something rather than says it.
class ShellNavBar extends StatelessWidget {
  const ShellNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<ShellNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double height = 58;
  static const double _indicatorWidth = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final index = selectedIndex.clamp(0, items.length - 1);

    return Material(
      color: theme.cardTheme.color ?? scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / items.length;
              return Stack(
                children: [
                  Row(
                    children: [
                      for (final (i, item) in items.indexed)
                        Expanded(
                          child: _NavButton(
                            item: item,
                            selected: i == index,
                            onTap: () {
                              if (i != index) HapticFeedback.selectionClick();
                              onSelected(i);
                            },
                          ),
                        ),
                    ],
                  ),
                  AnimatedPositioned(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: const Cubic(0.22, 0.72, 0.2, 1),
                    top: -1,
                    left: slot * (index + 0.5) - _indicatorWidth / 2,
                    width: _indicatorWidth,
                    height: 3,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ShellNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconTheme(
              data: IconThemeData(size: 24, color: color),
              child: selected ? item.selectedIcon : item.icon,
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label.toUpperCase(),
                  maxLines: 1,
                  style: Type.mono(9.5, tracking: 0.08, color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
