import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../formatters.dart';
import 'components.dart';
import 'tokens.dart';

/// The pieces every editor sheet in the set is assembled from.

/// A money input: the `GHS` code sits inside the box, on the baseline of the
/// digits, so the field reads as one figure rather than a label plus a number.
class MoneyField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  /// The oversized centred variant used at the top of Add transaction.
  final bool hero;

  const MoneyField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.hero = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    final field = TextFormField(
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      textAlign: hero ? TextAlign.center : TextAlign.start,
      style: hero
          ? AppType.heroFigure.copyWith(fontSize: 30, color: t.ink)
          : AppType.figure.copyWith(fontSize: 15, color: t.ink),
      cursorColor: t.brandInk,
      decoration: InputDecoration(
        hintText: hero ? '0.00' : null,
        hintStyle: hero
            ? AppType.heroFigure.copyWith(fontSize: 30, color: t.inkFaint)
            : null,
        isDense: true,
        prefixIcon: hero
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 13, right: 7),
                child: Text(kCurrencyCode,
                    style: AppType.label.copyWith(color: t.inkMuted)),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        contentPadding: hero
            ? const EdgeInsets.symmetric(vertical: 16)
            : const EdgeInsets.fromLTRB(0, 13, 13, 13),
      ),
    );

    if (hero) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.hairline),
            ),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(kCurrencyCode,
                    style: AppType.currencyCode
                        .copyWith(fontSize: 11, color: t.inkMuted)),
                field,
              ],
            ),
          ),
        ],
      );
    }

    return LabeledField(label: label, child: field);
  }
}

/// A plain text input with the label above it.
class SheetField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  const SheetField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLines = 1,
    this.autofocus = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return LabeledField(
      label: label,
      child: TextFormField(
        controller: controller,
        validator: validator,
        onChanged: onChanged,
        maxLines: maxLines,
        autofocus: autofocus,
        textCapitalization: textCapitalization,
        style: AppType.body.copyWith(fontSize: 15, height: 1.2, color: t.ink),
        cursorColor: t.brandInk,
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }
}

/// A row that opens a picker: label on the left, current value and a chevron
/// on the right.
class PickerRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const PickerRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        child: Row(
          children: [
            Text(label,
                style: AppType.bodySmall
                    .copyWith(fontSize: 14, height: 1.0, color: t.inkMuted)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppType.rowTitle.copyWith(height: 1.0, color: t.ink)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: t.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// A segmented row of equal-width options — Bank / Mobile Money / Cash.
class SegmentedChips<T> extends StatelessWidget {
  final String? label;
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const SegmentedChips({
    super.key,
    this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final row = Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: Material(
              color: options[i].$1 == selected
                  ? t.brand
                  : Theme.of(context).brightness == Brightness.light
                      ? t.card
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => onChanged(options[i].$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                        color: options[i].$1 == selected ? t.brand : t.outline),
                  ),
                  child: Text(
                    options[i].$2,
                    textAlign: TextAlign.center,
                    style: AppType.label.copyWith(
                      fontSize: 13,
                      fontWeight: options[i].$1 == selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: options[i].$1 == selected ? t.onBrand : t.inkBody,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    if (label == null) return row;
    return LabeledField(label: label!, child: row);
  }
}

/// The one destructive confirmation in the app.
///
/// It states what will happen to the numbers, not just that the thing will be
/// gone — "your Fidelity balance goes back up by that amount" is the part that
/// decides the answer. The safe choice is on the left and is not the red one.
Future<bool?> showDeleteConfirmation({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Keep it',
}) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) {
      final t = CediTokens.of(ctx);
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
          decoration: BoxDecoration(
            color: t.canvas,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.expense.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: AppType.title
                      .copyWith(fontSize: 19, height: 1.3, color: t.ink)),
              const SizedBox(height: 10),
              Text(message,
                  style: AppType.body.copyWith(height: 1.55, color: t.inkMuted)),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: cancelLabel,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DangerButton(
                      label: confirmLabel,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Opens any editor sheet on the standard surface.
Future<T?> showEditorSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SheetSurface(
      child: SingleChildScrollView(child: builder(ctx)),
    ),
  );
}
