import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/design/components.dart';
import 'package:personal_finance_app/core/theme.dart';

/// The defect that drove the redesign: `GHS 5,400.00` rendered as `GHS 5,…`
/// in a third-width card. Every figure slot is now designed at the worst case
/// the app can produce — minus sign, five significant digits, thousands
/// separator, two decimals — so these tests pin that down rather than the
/// number that happens to be on screen today.
const _worstCase = 12480.0;

/// The artboard width the set was drawn at.
const _phoneWidth = 390.0;

Future<void> pumpPhone(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(_phoneWidth, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: appDarkTheme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('three-up figure row at worst case', () {
    testWidgets('holds -12,480.00 in every column without truncating',
        (tester) async {
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            final t = CediTokens.of(context);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: FigureCard(
                        label: 'Income', amount: _worstCase, tint: t.income)),
                const SizedBox(width: 8),
                Expanded(
                    child: FigureCard(
                        label: 'Expense',
                        amount: _worstCase,
                        tint: t.expense,
                        negate: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: FigureCard(
                        label: 'Net',
                        amount: -_worstCase,
                        tint: t.neutral)),
              ],
            );
          },
        ),
      );

      // Two negatives and one positive, all rendered in full. An ellipsis
      // anywhere here means the row is back to hiding the number it exists
      // to show.
      expect(find.text('12,480.00'), findsOneWidget);
      expect(find.text('-12,480.00'), findsNWidgets(2));
      expect(find.textContaining('…'), findsNothing);

      // The currency code is drawn once per card, on its own line. That is
      // what frees the horizontal space the digits need.
      expect(find.text('GHS'), findsNWidgets(3));
    });

    testWidgets('draws the figure in the tint ink, never white on a fill',
        (tester) async {
      late CediTokens tokens;
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            tokens = CediTokens.of(context);
            return FigureCard(
                label: 'Expense',
                amount: _worstCase,
                tint: tokens.expense,
                negate: true);
          },
        ),
      );

      final figure = tester.widget<Text>(find.text('-12,480.00'));
      expect(figure.style!.color, tokens.expense.ink);
      expect(figure.style!.color, isNot(Colors.white));

      final card = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(TintCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.color, tokens.expense.surface);
    });

    testWidgets('does not overflow at a figure larger than the design case',
        (tester) async {
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            final t = CediTokens.of(context);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final amount in [-1234567.89, 987654.32, -12480.0])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FigureCard(
                          label: 'Net', amount: amount, tint: t.neutral),
                    ),
                  ),
              ],
            );
          },
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('-1,234,567.89'), findsOneWidget);
    });
  });

  group('transaction row', () {
    testWidgets('keeps the amount whole and lets the title give way',
        (tester) async {
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            final t = CediTokens.of(context);
            return RowGroup(
              children: [
                TxnRow(
                  leading: const CategoryGlyph(name: 'Transportation', hue: 1),
                  title: 'A merchant with a name far too long for one line',
                  subtitle: 'MTN Momo · 6:42 pm',
                  amount: '-GHS 12,480.00',
                  amountColor: t.expense.ink,
                ),
              ],
            );
          },
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('-GHS 12,480.00'), findsOneWidget);
      // The glyph is initials, not an icon: TR reads at 32px where a grey
      // pictogram does not.
      expect(find.text('TR'), findsOneWidget);
    });
  });
}
