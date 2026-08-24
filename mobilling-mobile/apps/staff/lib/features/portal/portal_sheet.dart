import 'package:flutter/material.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

/// The portal's action sheet: drag handle, an eyebrow naming the context, a
/// display title, then [builder]'s content.
///
/// Row actions on a phone live in a sheet rather than a row of icon buttons —
/// there is no room for five icons beside a list row. Rises with the keyboard
/// so a field near the bottom is never hidden behind it.
Future<T?> showPortalSheet<T>(
  BuildContext context, {
  required String title,
  String? eyebrow,
  bool padded = true,
  required Widget Function(BuildContext context, StateSetter setState) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      return StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padded ? Spacing.lg : Spacing.md,
              0,
              padded ? Spacing.lg : Spacing.md,
              Spacing.lg + sheetBottomInset(context),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: padded ? 0 : Spacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: Spacing.xs),
                        ],
                        Text(
                          title,
                          style: Type.display(
                            22,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  builder(context, setState),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
