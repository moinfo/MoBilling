import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

/// A rendered catalogue of the design system.
///
/// Its job is review, not regression: run
/// `flutter test --update-goldens packages/mobilling_ui` and look at
/// `test/goldens/catalogue-*.png` to see every scale of the money readout,
/// every status colour and both themes side by side, without needing a
/// device or a login. That it also fails on unintended visual change is a
/// bonus.
void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    testWidgets('catalogue — $name', (tester) async {
      tester.view
        ..physicalSize = const Size(900, 1500)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: const _Catalogue(),
        ),
      );

      await expectLater(
        find.byType(_Catalogue),
        matchesGoldenFile('goldens/catalogue-$name.png'),
      );
    });
  }
}

class _Catalogue extends StatelessWidget {
  const _Catalogue();

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;

    // Explicit box rather than a Scaffold: the test view has no bounded
    // size of its own, so a Scaffold body would be laid out at infinite
    // width and every button in here would assert.
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: 900,
        height: 1500,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: 48),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Money readout — every scale'),
              for (final scale in MoneyScale.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Money(1284350.5, scale: scale),
                ),
              const SizedBox(height: Spacing.md),
              const SectionHeader('Carrying state'),
              Row(
                children: [
                  Money(0, scale: MoneyScale.headline, color: status.settled),
                  const SizedBox(width: Spacing.lg),
                  Money(
                    -4200.75,
                    scale: MoneyScale.headline,
                    color: status.overdue,
                  ),
                  const SizedBox(width: Spacing.lg),
                  const Money(
                    89.9,
                    scale: MoneyScale.headline,
                    showCode: false,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              const SectionHeader('Alignment — the reason for tabular figures'),
              for (final v in [7.5, 1250.0, 98432.25, 1000000.0])
                Money(v, scale: MoneyScale.row),
              const SizedBox(height: Spacing.md),
              const SectionHeader('Counter rail'),
              StatRail(
                items: [
                  const StatRailItem(label: 'Services', value: '6'),
                  const StatRailItem(label: 'Domains', value: '11'),
                  StatRailItem(
                    label: 'Unpaid',
                    value: '6',
                    emphasis: status.attention,
                  ),
                  const StatRailItem(label: 'Tickets', value: '0'),
                ],
              ),
              const SizedBox(height: Spacing.md),
              const SectionHeader('Stat tiles'),
              SizedBox(
                height: 96,
                child: Row(
                  children: [
                    const Expanded(
                      child: StatTile.money(
                        label: 'Outstanding',
                        amount: 1284350.5,
                        icon: Icons.receipt_long_outlined,
                      ),
                    ),
                    Expanded(
                      child: StatTile.money(
                        label: 'Collected',
                        amount: 940100,
                        emphasis: status.settled,
                        icon: Icons.savings_outlined,
                      ),
                    ),
                    const Expanded(
                      child: StatTile(
                        label: 'Clients',
                        value: '1,204',
                        icon: Icons.people_outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
              const SectionHeader('Status'),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: const [
                  StatusChip('paid'),
                  StatusChip('sent'),
                  StatusChip('partial'),
                  StatusChip('overdue'),
                  StatusChip('draft'),
                ],
              ),
              const SizedBox(height: Spacing.md),
              const SectionHeader('Buttons'),
              Row(
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Pay now')),
                  const SizedBox(width: Spacing.sm),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Download PDF'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  TextButton(onPressed: () {}, child: const Text('Cancel')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
