import 'package:flutter/material.dart';

import '../formatters.dart';
import 'tokens.dart';

/// The shared pieces from the components row of the screen set, drawn once.
///
/// Every one of them obeys the same two rules: a figure is never white on a
/// saturated fill, and a currency slot is sized for `-GHS 12,480.00` rather
/// than for the number that happens to be in it today.

// ---------------------------------------------------------------------------
// Text bits
// ---------------------------------------------------------------------------

/// The mono all-caps line that classifies the block under it.
class Eyebrow extends StatelessWidget {
  final String text;
  final Color color;
  final double size;

  const Eyebrow(this.text, {super.key, required this.color, this.size = 10});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppType.eyebrow.copyWith(color: color, fontSize: size),
      );
}

/// Heading above a group of cards, with an optional action on the right.
class SectionRow extends StatelessWidget {
  final String title;

  /// A mono note — "3", "VS AUG". Mutually exclusive with [action] in practice.
  final String? note;
  final String? action;
  final VoidCallback? onAction;

  const SectionRow({
    super.key,
    required this.title,
    this.note,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: AppType.cardTitle.copyWith(color: t.ink)),
        const Spacer(),
        if (note != null)
          Text(note!, style: AppType.monoCaption.copyWith(color: t.inkFaint)),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Text(
              action!,
              style: AppType.label.copyWith(color: t.brandInk),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// The plain card: neutral fill, hairline, medium radius.
class CediCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  const CediCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = Radii.medium,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final br = BorderRadius.circular(radius);
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: br,
        border: Border.all(color: t.hairline),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: br,
      child: InkWell(borderRadius: br, onTap: onTap, child: body),
    );
  }
}

/// A card carrying a semantic meaning — the tinted surface, its border, and
/// content drawn in inks of the same hue.
class TintCard extends StatelessWidget {
  final SemanticTint tint;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  const TintCard({
    super.key,
    required this.tint,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = Radii.medium,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint.surface,
        borderRadius: br,
        border: Border.all(color: tint.border),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: br,
      child: InkWell(borderRadius: br, onTap: onTap, child: body),
    );
  }
}

// ---------------------------------------------------------------------------
// Figures
// ---------------------------------------------------------------------------

/// A headline figure in a tinted card.
///
/// The currency code sits on its own line above the digits. That is the whole
/// trick behind the three-up row: a 114px column that would have truncated
/// `GHS 12,480.00` on one line holds `-12,480.00` comfortably on two.
class FigureCard extends StatelessWidget {
  final String label;
  final double amount;
  final SemanticTint tint;

  /// True for the two-up row, which gets the 22px figure.
  final bool large;

  /// Forces the sign even when the amount is positive — an expense total is
  /// stored unsigned but reads as money leaving.
  final bool negate;

  final VoidCallback? onTap;

  const FigureCard({
    super.key,
    required this.label,
    required this.amount,
    required this.tint,
    this.large = false,
    this.negate = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final value = negate ? -amount.abs() : amount;
    return TintCard(
      tint: tint,
      onTap: onTap,
      padding: large
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.figureLabel.copyWith(
              color: tint.body,
              fontSize: large ? 11 : 10,
              letterSpacing: large ? 0.44 : 0,
            ),
          ),
          SizedBox(height: large ? 8 : 7),
          Text(kCurrencyCode,
              style: AppType.currencyCode.copyWith(
                color: tint.muted,
                fontSize: large ? 10 : 9,
              )),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              moneyDigits(value),
              maxLines: 1,
              softWrap: false,
              style: (large ? AppType.figureLarge : AppType.figure)
                  .copyWith(color: tint.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// A supporting stat under the hero — label, code, figure, no fill of its own.
class StatColumn extends StatelessWidget {
  final String label;
  final double amount;
  final Color labelColor;
  final Color codeColor;
  final Color inkColor;

  const StatColumn({
    super.key,
    required this.label,
    required this.amount,
    required this.labelColor,
    required this.codeColor,
    required this.inkColor,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.figureLabel.copyWith(color: labelColor, height: 1.3),
          ),
          const SizedBox(height: 6),
          Text(kCurrencyCode,
              style: AppType.currencyCode.copyWith(color: codeColor)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              moneyDigits(amount),
              maxLines: 1,
              softWrap: false,
              style: AppType.figure.copyWith(color: inkColor),
            ),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Glyphs and rows
// ---------------------------------------------------------------------------

/// The two-letter plate that stands in for a category or account.
///
/// Initials rather than icons: at 32px a Material glyph for "Gifts &
/// Donations" and one for "Groceries" are the same grey blob, while GF and GD
/// are not.
class CategoryGlyph extends StatelessWidget {
  final String name;

  /// Position in the 12-hue categorical palette. Pass the same index the chart
  /// used so the row and its bar segment agree.
  final int hue;
  final double size;

  /// Transfers are colourless on purpose — your own money changing seats.
  final bool neutral;

  const CategoryGlyph({
    super.key,
    required this.name,
    required this.hue,
    this.size = 32,
    this.neutral = false,
  });

  static String initials(String name) {
    final words = name
        .split(RegExp(r'[\s&/_-]+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w))
        .toList();
    if (words.isEmpty) return '??';
    if (words.length == 1) {
      final w = words.first;
      return (w.length == 1 ? w : w.substring(0, 2)).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final i = hue.abs() % t.glyphSurfaces.length;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: neutral ? t.track : t.glyphSurfaces[i],
        shape: BoxShape.circle,
      ),
      child: Text(
        neutral ? '⇆' : initials(name),
        style: TextStyle(
          fontFamily: AppType.sans,
          fontSize: neutral ? size * 0.38 : size * 0.32,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: neutral ? t.inkMuted : t.glyphInks[i],
        ),
      ),
    );
  }
}

/// One line of a transaction list: glyph, title over subtitle, signed figure.
class TxnRow extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Already signed and formatted — `-GHS 47.00`.
  final String amount;
  final Color amountColor;
  final Widget leading;
  final VoidCallback? onTap;

  const TxnRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
    required this.leading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle.copyWith(color: t.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowSub.copyWith(color: t.inkMuted)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(amount,
                softWrap: false,
                style: AppType.figureRow.copyWith(color: amountColor)),
          ],
        ),
      ),
    );
  }
}

/// A card whose children are rows separated by inset rules.
class RowGroup extends StatelessWidget {
  final List<Widget> children;
  const RowGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: Radii.md,
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: t.rule),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------

/// Three steps, not "everything is red".
///
/// The scale is carried by the dot as much as the fill: solid for something
/// that breaks, hollow-with-a-thick-ring for something tight, a thin outline
/// for something merely worth knowing.
enum AlertTone { critical, tight, info }

class AlertCard extends StatelessWidget {
  final AlertTone tone;

  /// The mono classifier — "NOT COVERED", "TIGHT", "FOR INFO".
  final String eyebrow;

  /// The sentence that states the situation, with its figures.
  final String message;

  /// The evidence behind [message]. Optional: an alert that needs no working
  /// shown is better without it.
  final String? detail;

  /// Text of the inline action, drawn as a link at the foot of the card.
  final String? actionLabel;

  final VoidCallback? onTap;

  const AlertCard({
    super.key,
    required this.tone,
    required this.eyebrow,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final tint = switch (tone) {
      AlertTone.critical => t.expense,
      AlertTone.tight => t.warning,
      AlertTone.info => t.neutral,
    };
    final dotColor = switch (tone) {
      AlertTone.critical => t.expense.ink,
      AlertTone.tight => t.warning.ink,
      AlertTone.info => t.inkMuted,
    };

    return TintCard(
      tint: tint,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: _Dot(tone: tone, color: dotColor),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Eyebrow(eyebrow,
                    color: tone == AlertTone.info ? t.inkMuted : tint.muted),
                const SizedBox(height: 6),
                Text(message,
                    style: AppType.body.copyWith(color: tint.body)),
                if (detail != null) ...[
                  const SizedBox(height: 5),
                  Text(detail!,
                      style: AppType.bodySmall.copyWith(
                          height: 1.45,
                          color: tone == AlertTone.info
                              ? t.inkMuted
                              : tint.muted)),
                ],
                if (actionLabel != null && onTap != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(actionLabel!,
                          style: AppType.label.copyWith(
                              fontSize: 13,
                              color: tone == AlertTone.info
                                  ? t.brandInk
                                  : tint.ink)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward,
                          size: 14,
                          color: tone == AlertTone.info ? t.brandInk : tint.ink),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final AlertTone tone;
  final Color color;
  const _Dot({required this.tone, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tone == AlertTone.critical ? color : null,
          border: tone == AlertTone.critical
              ? null
              : Border.all(color: color, width: tone == AlertTone.tight ? 2 : 1),
        ),
      );
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// The filled action. One per screen, and it lives in the bottom third.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final disabled = onPressed == null && !loading;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: disabled ? t.disabledFill : t.brand,
        borderRadius: Radii.sm,
        child: InkWell(
          borderRadius: Radii.sm,
          onTap: loading ? null : onPressed,
          splashColor: t.brandPressed,
          highlightColor: t.brandPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading) ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.onBrand,
                      backgroundColor: t.onBrand.withValues(alpha: 0.35),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: AppType.button.copyWith(
                    color: disabled
                        ? t.disabledInk
                        : loading
                            ? t.onBrand.withValues(alpha: 0.72)
                            : t.onBrand,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The outlined action — the second choice on a screen that offers two.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// Renders on the card fill rather than transparent. Light mode needs it so
  /// the button does not disappear into the canvas.
  final bool filled;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: filled ? t.card : Colors.transparent,
        borderRadius: Radii.sm,
        child: InkWell(
          borderRadius: Radii.sm,
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              borderRadius: Radii.sm,
              border: Border.all(color: t.outline),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppType.button.copyWith(
                  fontWeight: FontWeight.w600, color: t.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// The wide, quiet, brand-tinted row that asks the dashboard's one question.
class BrandPromptButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const BrandPromptButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? t.brand.withValues(alpha: 0.1) : t.card,
      borderRadius: Radii.sm,
      child: InkWell(
        borderRadius: Radii.sm,
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: Radii.sm,
            border: Border.all(color: t.safe.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppType.label.copyWith(
                    fontSize: 15,
                    color: dark ? const Color(0xFFBFEEE2) : t.safe.ink,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward, size: 17, color: t.brandInk),
            ],
          ),
        ),
      ),
    );
  }
}

/// A destructive action. Tinted, never a solid red slab.
class DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const DangerButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: t.expense.surface,
        borderRadius: Radii.sm,
        child: InkWell(
          borderRadius: Radii.sm,
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              borderRadius: Radii.sm,
              border: Border.all(color: t.expense.border),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: AppType.button
                    .copyWith(fontSize: 15, color: t.expense.ink)),
          ),
        ),
      ),
    );
  }
}

/// A label sitting above its field, plus the error line under it.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? error;

  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppType.label.copyWith(color: t.inkMuted)),
        const SizedBox(height: 7),
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!,
              style: AppType.bodySmall
                  .copyWith(fontSize: 12, height: 1.4, color: t.expense.ink)),
        ],
      ],
    );
  }
}

/// The segmented control at the top of Reports.
class SegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: t.card, borderRadius: Radii.sm),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index ? t.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: AppType.label.copyWith(
                      fontSize: 13,
                      fontWeight:
                          i == index ? FontWeight.w700 : FontWeight.w600,
                      color: i == index ? t.onBrand : t.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Previous / next around a label — the week stepper on Reports.
class PeriodStepper extends StatelessWidget {
  final String title;
  final String caption;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTapTitle;

  const PeriodStepper({
    super.key,
    required this.title,
    required this.caption,
    this.onPrevious,
    this.onNext,
    this.onTapTitle,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return CediCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      radius: Radii.small + 2,
      child: Row(
        children: [
          _StepArrow(icon: Icons.chevron_left, onTap: onPrevious),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapTitle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: AppType.cardTitle
                          .copyWith(fontSize: 14, color: t.ink)),
                  const SizedBox(height: 5),
                  Text(caption.toUpperCase(),
                      style: AppType.monoCaption.copyWith(color: t.inkFaint)),
                ],
              ),
            ),
          ),
          _StepArrow(icon: Icons.chevron_right, onTap: onNext),
        ],
      ),
    );
  }
}

class _StepArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepArrow({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon,
          size: 22,
          color: onTap == null ? t.inkFaint.withValues(alpha: 0.4) : t.inkMuted),
    );
  }
}

/// A square-cornered icon button in a hairline box — refresh, settings.
class IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: dark ? Colors.transparent : t.card,
        borderRadius: Radii.sm,
        child: InkWell(
          borderRadius: Radii.sm,
          onTap: onPressed,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: Radii.sm,
              border: Border.all(color: dark ? t.hairline : t.fieldBorder),
            ),
            child: Icon(icon, size: 17, color: t.inkMuted),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bars
// ---------------------------------------------------------------------------

class BarSlice {
  final double value;
  final Color color;
  const BarSlice(this.value, this.color);
}

/// The stacked bar used for money placement and for share-of-expenses.
class StackedBar extends StatelessWidget {
  final List<BarSlice> slices;
  final double height;

  const StackedBar({super.key, required this.slices, this.height = 12});

  @override
  Widget build(BuildContext context) {
    final shown = slices.where((s) => s.value > 0).toList();
    if (shown.isEmpty) {
      final t = CediTokens.of(context);
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: t.track,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              flex: (shown[i].value * 10000).round().clamp(1, 100000000),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(height / 2),
                child: Container(color: shown[i].color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One legend line: swatch, label, and a figure hard against the right edge.
class LegendLine extends StatelessWidget {
  final Color color;
  final String label;

  /// The right-hand figure, already formatted.
  final String? trailing;

  /// A percentage that sits between the label and the figure.
  final String? middle;

  const LegendLine({
    super.key,
    required this.color,
    required this.label,
    this.trailing,
    this.middle,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodySmall.copyWith(height: 1.0, color: t.inkBody)),
        ),
        if (middle != null) ...[
          Text(middle!,
              style: AppType.label
                  .copyWith(fontSize: 12, color: t.inkMuted)),
          const SizedBox(width: 9),
        ],
        if (trailing != null)
          Text(trailing!,
              softWrap: false,
              style: AppType.figureRow.copyWith(fontSize: 13, color: t.ink)),
      ],
    );
  }
}

/// A goal or floor meter: title, `x / y`, and a filled track.
class ProgressMeter extends StatelessWidget {
  final String label;
  final String trailing;
  final double fraction;
  final Color color;

  const ProgressMeter({
    super.key,
    required this.label,
    required this.trailing,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(fontSize: 13, color: t.ink)),
            ),
            Text(trailing,
                style: AppType.label.copyWith(
                  fontSize: 13,
                  color: t.inkMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: t.track,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty and error
// ---------------------------------------------------------------------------

/// Dashed outline, one sentence about what to do, one button.
class EmptyCard extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyCard({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return DottedBorderBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: AppType.rowTitle.copyWith(fontSize: 15, color: t.ink)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: AppType.bodySmall
                  .copyWith(height: 1.5, color: t.inkMuted)),
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            Material(
              color: t.brand,
              borderRadius: Radii.sm,
              child: InkWell(
                borderRadius: Radii.sm,
                onTap: onAction,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Text(actionLabel!,
                      style: AppType.button
                          .copyWith(fontSize: 14, color: t.onBrand)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The dashed container behind [EmptyCard], kept separate so other empty
/// states can borrow it.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DottedBorderBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return CustomPaint(
      painter: _DashedRectPainter(color: t.outline, radius: Radii.medium),
      child: Container(
        width: double.infinity,
        padding: padding,
        child: child,
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// Something failed to load. Tinted, with the retry as an outline on the tint.
class ErrorCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorCard({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return TintCard(
      tint: t.expense,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: AppType.rowTitle
                  .copyWith(fontSize: 15, color: t.expense.body)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: AppType.bodySmall
                  .copyWith(height: 1.5, color: t.expense.muted)),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              borderRadius: Radii.sm,
              child: InkWell(
                borderRadius: Radii.sm,
                onTap: onRetry,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: Radii.sm,
                    border: Border.all(
                        color: t.expense.ink.withValues(alpha: 0.5)),
                  ),
                  child: Text('Retry',
                      style: AppType.button
                          .copyWith(fontSize: 14, color: t.expense.ink)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chips, search and sheets
// ---------------------------------------------------------------------------

/// A pill that is either on or off.
///
/// Selection is carried by a filled brand pill, not by a tick or a tint — at
/// chip size a tick is invisible and a tint reads the same as no tint at all.
class SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// The quieter, smaller pill used in the active-filter strip.
  final bool compact;

  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(11);

    return Material(
      color: selected
          ? t.brand
          : light
              ? t.card
              : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 13,
            vertical: compact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: selected ? t.brand : t.outline),
          ),
          child: Text(
            label,
            style: AppType.label.copyWith(
              fontSize: compact ? 12 : 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? t.onBrand : t.inkBody,
            ),
          ),
        ),
      ),
    );
  }
}

/// The search box, with the filter button that sits beside it carrying a count.
class SearchRow extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  /// How many filters are on. Zero draws the button quiet; anything else draws
  /// it in brand, so the user is never left wondering why the list is short.
  final int filterCount;
  final VoidCallback? onFilter;

  const SearchRow({
    super.key,
    required this.controller,
    required this.hint,
    required this.filterCount,
    this.onChanged,
    this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = filterCount > 0;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: AppType.body.copyWith(fontSize: 14, height: 1.2, color: t.ink),
            cursorColor: t.brandInk,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 17, color: t.inkMuted),
                      onPressed: () {
                        controller.clear();
                        onChanged?.call('');
                      },
                    ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 38, minHeight: 38),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: on
              ? (dark ? t.brand.withValues(alpha: 0.12) : t.safe.surface)
              : Colors.transparent,
          borderRadius: Radii.sm,
          child: InkWell(
            borderRadius: Radii.sm,
            onTap: onFilter,
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: Radii.sm,
                border: Border.all(color: on ? t.safe.border : t.fieldBorder),
              ),
              child: on
                  ? Text('$filterCount',
                      style: AppType.label
                          .copyWith(fontSize: 14, color: t.brandInk))
                  : Icon(Icons.tune, size: 19, color: t.inkMuted),
            ),
          ),
        ),
      ],
    );
  }
}

/// The date rule above a day's transactions, with that day's net.
class DayHeader extends StatelessWidget {
  final String label;

  /// Already formatted and signed.
  final String amount;
  final Color amountColor;

  const DayHeader({
    super.key,
    required this.label,
    required this.amount,
    required this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.eyebrow.copyWith(
                    fontSize: 12, letterSpacing: 0.96, color: t.inkMuted)),
          ),
          const SizedBox(width: 10),
          Text(amount,
              softWrap: false,
              style: AppType.figureRow.copyWith(fontSize: 13, color: amountColor)),
        ],
      ),
    );
  }
}

/// The modal surface every sheet in the set sits on: grab handle, rounded top,
/// canvas fill, and room for the keyboard.
class SheetSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SheetSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 22),
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.canvas,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(Radii.large)),
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: t.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// A sheet's title line, with an optional text action on the right.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SheetHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(title,
              style: AppType.title.copyWith(fontSize: 20, color: t.ink)),
        ),
        if (action != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Text(action!,
                style: AppType.label.copyWith(fontSize: 13, color: t.brandInk)),
          ),
      ],
    );
  }
}

/// The mono label above a group of controls inside a sheet.
class GroupLabel extends StatelessWidget {
  final String text;
  const GroupLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Eyebrow(text, size: 11, color: CediTokens.of(context).inkFaint),
      );
}

/// A wrapped run of [SelectChip]s under a [GroupLabel].
class ChipGroup extends StatelessWidget {
  final String label;
  final List<String> options;

  /// Null means "all" — no chip is lit.
  final String? selected;
  final ValueChanged<String?> onChanged;

  const ChipGroup({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GroupLabel(label),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final option in options)
                SelectChip(
                  label: option,
                  selected: option == selected,
                  // Tapping the lit chip clears it. A filter you cannot turn
                  // off without hunting for a Reset button is a trap.
                  onTap: () => onChanged(option == selected ? null : option),
                ),
            ],
          ),
        ],
      );
}
