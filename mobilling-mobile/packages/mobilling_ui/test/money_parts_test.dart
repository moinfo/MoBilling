import 'package:flutter_test/flutter_test.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

/// [Formatting.parts] feeds the money readout, which sets each piece at a
/// different size. A wrong split is not a formatting bug there — it puts a
/// minus sign or a digit into the small grey run, which silently misstates
/// an amount.
void main() {
  setUp(() => Formatting.setTenantCurrency('TZS'));

  test('splits a grouped amount into code, integer and cents', () {
    final p = Formatting.parts(1284350.5);
    expect(p.code, 'TZS');
    expect(p.whole, '1,284,350');
    expect(p.fraction, '50');
    expect(p.isNegative, isFalse);
    expect(p.plain, 'TZS 1,284,350.50');
  });

  test('the minus stays on the integer run, not in the cents', () {
    final p = Formatting.parts(-4200.75);
    expect(p.whole, '-4,200');
    expect(p.fraction, '75');
    expect(p.isNegative, isTrue);
  });

  test('cents are always two digits', () {
    expect(Formatting.parts(7).fraction, '00');
    expect(Formatting.parts(7.5).fraction, '50');
    // Rounds rather than truncating, so the parts agree with what
    // Formatting.currency would print for the same value. Not 7.005 — that
    // is 7.00499… as a double and rounds down, which is a property of binary
    // floats rather than of this code.
    expect(Formatting.parts(7.006).fraction, '01');
  });

  test('accepts the decimal strings Laravel emits', () {
    expect(Formatting.parts('1250.00').whole, '1,250');
    expect(Formatting.parts('1250.00').fraction, '00');
  });

  test('unparseable and null amounts read as zero, never as a crash', () {
    // Dashboards legitimately omit fields the caller may not see.
    expect(Formatting.parts(null).plain, 'TZS 0.00');
    expect(Formatting.parts('n/a').plain, 'TZS 0.00');
  });

  test('an explicit code overrides the tenant currency', () {
    expect(Formatting.parts(10, currencyCode: 'USD').code, 'USD');
  });

  test('parts and currency() never disagree', () {
    for (final v in [0, 7.005, 1250, -4200.75, 98432.255, 1000000]) {
      expect(Formatting.parts(v).plain, Formatting.currency(v), reason: '$v');
    }
  });
}
