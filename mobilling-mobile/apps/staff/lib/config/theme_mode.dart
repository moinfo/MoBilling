import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The person's light/dark choice, persisted across launches.
///
/// `system` is the default and means "follow the phone". Tapping the toggle
/// on the sign-in screen pins one or the other, the same way the web's
/// header toggle writes `mobilling-theme` to localStorage. Stored as a tiny
/// file in the app's support directory rather than the keychain — it is a
/// preference, not a secret, and it must survive sign-out.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _fileName = 'theme_mode';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> _load() async {
    try {
      final raw = (await (await _file()).readAsString()).trim();
      final stored = ThemeMode.values.where((m) => m.name == raw).firstOrNull;
      if (stored != null && stored != state) state = stored;
    } on FileSystemException {
      // First launch, or the file is gone — system it is.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await (await _file()).writeAsString(mode.name, flush: true);
    } on FileSystemException {
      // Preference still applies for this session; it just won't persist.
    }
  }

  /// Flip between light and dark, resolving `system` against what the phone
  /// is showing right now so the first tap always visibly changes something.
  Future<void> toggle(Brightness current) => set(
        current == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
      );
}

final NotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// The handoff's 38×38 radius-11 theme toggle: sun when dark (tap for
/// light), moon when light (tap for dark). [onInk] draws the translucent
/// variant for the brand panel.
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key, this.onInk = false});

  final bool onInk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final isDark = brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: Material(
        color: onInk
            ? Colors.white.withValues(alpha: 0.08)
            : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: onInk
                ? Colors.white.withValues(alpha: 0.16)
                : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () =>
              ref.read(themeModeProvider.notifier).toggle(brightness),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20,
              color: onInk ? Colors.white : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// System / Light / Dark as one segmented control — for Settings and the
/// account sheet, where there is room to show the third option the
/// sign-in toggle folds away.
class AppearanceControl extends ConsumerWidget {
  const AppearanceControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined, size: 18),
            label: Text('System')),
        ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined, size: 18),
            label: Text('Light')),
        ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined, size: 18),
            label: Text('Dark')),
      ],
      selected: {mode},
      onSelectionChanged: (s) =>
          ref.read(themeModeProvider.notifier).set(s.first),
      showSelectedIcon: false,
    );
  }
}
