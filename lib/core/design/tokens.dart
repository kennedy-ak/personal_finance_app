import 'package:flutter/material.dart';

/// Every colour in the redesigned screen set, resolved per theme.
///
/// The rule the set is built on: **no saturated fill ever carries a figure**.
/// A semantic block is a low-alpha tint, a border of the same hue, and an ink
/// that is a legible tint of that hue. So each semantic family arrives as a
/// triple — [surface], [border], [ink] — plus a [muted] for the caption line
/// that sits above the number.
@immutable
class SemanticTint {
  /// The card fill.
  final Color surface;

  /// The 1px hairline around it.
  final Color border;

  /// The figure itself. Contrast-checked against [surface].
  final Color ink;

  /// The label and the `GHS` code above the figure.
  final Color muted;

  /// The caption line, one step down from [ink] but still on-hue.
  final Color body;

  const SemanticTint({
    required this.surface,
    required this.border,
    required this.ink,
    required this.muted,
    required this.body,
  });

  SemanticTint lerpTo(SemanticTint other, double t) => SemanticTint(
        surface: Color.lerp(surface, other.surface, t)!,
        border: Color.lerp(border, other.border, t)!,
        ink: Color.lerp(ink, other.ink, t)!,
        muted: Color.lerp(muted, other.muted, t)!,
        body: Color.lerp(body, other.body, t)!,
      );
}

/// The design tokens, reachable from any widget via `CediTokens.of(context)`.
@immutable
class CediTokens extends ThemeExtension<CediTokens> {
  // ---- surfaces -----------------------------------------------------------
  /// Page background.
  final Color canvas;

  /// Default card fill.
  final Color card;

  /// A card that is one step recessed — archived accounts, disabled fills.
  final Color recessed;

  /// The bottom navigation bar, which sits slightly proud of the canvas.
  final Color navBar;

  /// Hairline on a neutral card.
  final Color hairline;

  /// The divider inside a card, lighter than [hairline].
  final Color rule;

  // ---- ink ----------------------------------------------------------------
  /// Headlines and figures.
  final Color ink;

  /// Body copy inside a card.
  final Color inkBody;

  /// Captions, account subtitles, secondary figures.
  final Color inkMuted;

  /// The quietest text in the set: mono eyebrows, placeholder text.
  final Color inkFaint;

  // ---- brand --------------------------------------------------------------
  /// The filled-button and active-tab colour.
  final Color brand;

  /// Text drawn on top of [brand].
  final Color onBrand;

  /// [brand] pressed.
  final Color brandPressed;

  /// A brand-coloured link or text action on the page background.
  final Color brandInk;

  // ---- semantics ----------------------------------------------------------
  final SemanticTint income;
  final SemanticTint expense;
  final SemanticTint warning;
  final SemanticTint safe;
  final SemanticTint accent;

  /// The neutral member of the figure-card family — "Net", "Transfer".
  final SemanticTint neutral;

  // ---- placement bar ------------------------------------------------------
  final Color liquid;
  final Color committed;
  final Color protected;

  /// Track behind a progress meter or placement bar.
  final Color track;

  // ---- controls -----------------------------------------------------------
  /// Field fill.
  final Color field;

  /// Field hairline at rest.
  final Color fieldBorder;

  /// Field hairline in error.
  final Color fieldBorderError;

  /// Field fill in error. Dark mode tints it; light mode keeps it white and
  /// lets the border carry the state.
  final Color fieldError;

  /// Outlined-button and chip hairline.
  final Color outline;

  /// Disabled filled-button fill and its text.
  final Color disabledFill;
  final Color disabledInk;

  /// Category-glyph palette, indexed by hue family. Keys match
  /// `AppColors.chart` positions so a category keeps its colour everywhere.
  final List<Color> glyphSurfaces;
  final List<Color> glyphInks;

  const CediTokens({
    required this.canvas,
    required this.card,
    required this.recessed,
    required this.navBar,
    required this.hairline,
    required this.rule,
    required this.ink,
    required this.inkBody,
    required this.inkMuted,
    required this.inkFaint,
    required this.brand,
    required this.onBrand,
    required this.brandPressed,
    required this.brandInk,
    required this.income,
    required this.expense,
    required this.warning,
    required this.safe,
    required this.accent,
    required this.neutral,
    required this.liquid,
    required this.committed,
    required this.protected,
    required this.track,
    required this.field,
    required this.fieldBorder,
    required this.fieldBorderError,
    required this.fieldError,
    required this.outline,
    required this.disabledFill,
    required this.disabledInk,
    required this.glyphSurfaces,
    required this.glyphInks,
  });

  static CediTokens of(BuildContext context) =>
      Theme.of(context).extension<CediTokens>() ?? dark;

  /// Dark is the primary theme. It was designed first; light is the port.
  static const dark = CediTokens(
    canvas: Color(0xFF0F1413),
    card: Color(0xFF1A2120),
    recessed: Color(0xFF151A19),
    navBar: Color(0xFF161C1B),
    hairline: Color(0x12FFFFFF),
    rule: Color(0x0FFFFFFF),
    ink: Color(0xFFE8EDEB),
    inkBody: Color(0xFFC9D3D0),
    inkMuted: Color(0xFF8A9A96),
    inkFaint: Color(0xFF6D7C78),
    brand: Color(0xFF0E7C66),
    onBrand: Color(0xFFEAFBF6),
    brandPressed: Color(0xFF0A5A4A),
    brandInk: Color(0xFF4FD1B0),
    income: SemanticTint(
      surface: Color(0xFF1A2E24),
      border: Color(0x4716A34A),
      ink: Color(0xFF4ADE80),
      muted: Color(0xFF7CBF9A),
      body: Color(0xFF8FDCAE),
    ),
    expense: SemanticTint(
      surface: Color(0xFF2D2120),
      border: Color(0x47DC2626),
      ink: Color(0xFFFCA5A5),
      muted: Color(0xFFC98E8E),
      body: Color(0xFFF5DEDE),
    ),
    warning: SemanticTint(
      surface: Color(0xFF2B2519),
      border: Color(0x47F59E0B),
      ink: Color(0xFFFBBF24),
      muted: Color(0xFFE9C77E),
      body: Color(0xFFF2E7D2),
    ),
    safe: SemanticTint(
      surface: Color(0xFF132A25),
      border: Color(0x660E7C66),
      ink: Color(0xFF7FEBD1),
      muted: Color(0xFF7FC7B4),
      body: Color(0xFF95B3AB),
    ),
    accent: SemanticTint(
      surface: Color(0xFF221F2E),
      border: Color(0x578B5CF6),
      ink: Color(0xFFC4B5FD),
      muted: Color(0xFFA99FD0),
      body: Color(0xFFEAE6FA),
    ),
    neutral: SemanticTint(
      surface: Color(0xFF1A2120),
      border: Color(0x17FFFFFF),
      ink: Color(0xFFE8EDEB),
      muted: Color(0xFF6D7C78),
      body: Color(0xFFC9D3D0),
    ),
    liquid: Color(0xFF16A34A),
    committed: Color(0xFFF59E0B),
    protected: Color(0xFF8B5CF6),
    track: Color(0x14FFFFFF),
    field: Color(0xFF1A2120),
    fieldBorder: Color(0x1FFFFFFF),
    fieldBorderError: Color(0x80DC2626),
    fieldError: Color(0xFF221A1A),
    outline: Color(0x2EFFFFFF),
    disabledFill: Color(0xFF1C2422),
    disabledInk: Color(0xFF546260),
    glyphSurfaces: [
      Color(0x330E7C66),
      Color(0x2EF59E0B),
      Color(0x2E8B5CF6),
      Color(0x2EEF4444),
      Color(0x2E3B82F6),
      Color(0x2EEC4899),
      Color(0x2E14B8A6),
      Color(0x2EEAB308),
      Color(0x2E6366F1),
      Color(0x2E10B981),
      Color(0x2EF97316),
      Color(0x2E06B6D4),
    ],
    glyphInks: [
      Color(0xFF4FD1B0),
      Color(0xFFFCD34D),
      Color(0xFFC4B5FD),
      Color(0xFFFCA5A5),
      Color(0xFF93C5FD),
      Color(0xFFF9A8D4),
      Color(0xFF5EEAD4),
      Color(0xFFFDE047),
      Color(0xFFA5B4FC),
      Color(0xFF6EE7B7),
      Color(0xFFFDBA74),
      Color(0xFF67E8F9),
    ],
  );

  static const light = CediTokens(
    canvas: Color(0xFFF6F8F7),
    card: Color(0xFFFFFFFF),
    recessed: Color(0xFFF0F3F2),
    navBar: Color(0xFFFFFFFF),
    hairline: Color(0xFFE3E9E7),
    rule: Color(0xFFEDF1F0),
    ink: Color(0xFF0F1413),
    inkBody: Color(0xFF31403C),
    inkMuted: Color(0xFF5C6B67),
    inkFaint: Color(0xFF7C8B87),
    brand: Color(0xFF0B6455),
    onBrand: Color(0xFFF0FBF8),
    brandPressed: Color(0xFF084A3F),
    brandInk: Color(0xFF0B6455),
    income: SemanticTint(
      surface: Color(0xFFEDF8F1),
      border: Color(0xFFBFE3CC),
      ink: Color(0xFF166534),
      muted: Color(0xFF4E8464),
      body: Color(0xFF2F6B47),
    ),
    expense: SemanticTint(
      surface: Color(0xFFFCF0F0),
      border: Color(0xFFEDBFBF),
      ink: Color(0xFF991B1B),
      muted: Color(0xFFB06A6A),
      body: Color(0xFF5B2222),
    ),
    warning: SemanticTint(
      surface: Color(0xFFFDF6E7),
      border: Color(0xFFEFDCB0),
      ink: Color(0xFFB45309),
      muted: Color(0xFF92400E),
      body: Color(0xFF53360C),
    ),
    safe: SemanticTint(
      surface: Color(0xFFE8F5F0),
      border: Color(0xFFB7DED2),
      ink: Color(0xFF0A4C40),
      muted: Color(0xFF628B80),
      body: Color(0xFF41645B),
    ),
    accent: SemanticTint(
      surface: Color(0xFFF4F1FE),
      border: Color(0xFFD6CBFA),
      ink: Color(0xFF5B34C4),
      muted: Color(0xFF584B85),
      body: Color(0xFF251656),
    ),
    neutral: SemanticTint(
      surface: Color(0xFFFFFFFF),
      border: Color(0xFFE3E9E7),
      ink: Color(0xFF0F1413),
      muted: Color(0xFF7C8B87),
      body: Color(0xFF31403C),
    ),
    liquid: Color(0xFF1E874A),
    committed: Color(0xFFD08A0B),
    protected: Color(0xFF6D3FE0),
    track: Color(0xFFEDF1F0),
    field: Color(0xFFFFFFFF),
    fieldBorder: Color(0xFFD3DBD9),
    fieldBorderError: Color(0xFFDC2626),
    fieldError: Color(0xFFFFFFFF),
    outline: Color(0xFFC8D2CF),
    disabledFill: Color(0xFFE7ECEA),
    disabledInk: Color(0xFFA3AFAC),
    glyphSurfaces: [
      Color(0xFFDCEFEA),
      Color(0xFFFDF0D9),
      Color(0xFFEDE7FB),
      Color(0xFFFBE0E0),
      Color(0xFFDEEAFB),
      Color(0xFFFBE3EE),
      Color(0xFFD8F2EE),
      Color(0xFFFAF0CC),
      Color(0xFFE4E5FB),
      Color(0xFFD9F2E5),
      Color(0xFFFDEBDC),
      Color(0xFFD8EFF6),
    ],
    glyphInks: [
      Color(0xFF0B6455),
      Color(0xFF92400E),
      Color(0xFF5B34C4),
      Color(0xFFB91C1C),
      Color(0xFF1D4ED8),
      Color(0xFF9D174D),
      Color(0xFF0F766E),
      Color(0xFF854D0E),
      Color(0xFF3730A3),
      Color(0xFF047857),
      Color(0xFFB54A08),
      Color(0xFF155E75),
    ],
  );

  /// Tint for a transaction or figure that is money coming in.
  SemanticTint tintFor(bool isIncome) => isIncome ? income : expense;

  @override
  CediTokens copyWith() => this;

  @override
  CediTokens lerp(ThemeExtension<CediTokens>? other, double t) {
    if (other is! CediTokens) return this;
    return CediTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      recessed: Color.lerp(recessed, other.recessed, t)!,
      navBar: Color.lerp(navBar, other.navBar, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkBody: Color.lerp(inkBody, other.inkBody, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      brandPressed: Color.lerp(brandPressed, other.brandPressed, t)!,
      brandInk: Color.lerp(brandInk, other.brandInk, t)!,
      income: income.lerpTo(other.income, t),
      expense: expense.lerpTo(other.expense, t),
      warning: warning.lerpTo(other.warning, t),
      safe: safe.lerpTo(other.safe, t),
      accent: accent.lerpTo(other.accent, t),
      neutral: neutral.lerpTo(other.neutral, t),
      liquid: Color.lerp(liquid, other.liquid, t)!,
      committed: Color.lerp(committed, other.committed, t)!,
      protected: Color.lerp(protected, other.protected, t)!,
      track: Color.lerp(track, other.track, t)!,
      field: Color.lerp(field, other.field, t)!,
      fieldBorder: Color.lerp(fieldBorder, other.fieldBorder, t)!,
      fieldBorderError: Color.lerp(fieldBorderError, other.fieldBorderError, t)!,
      fieldError: Color.lerp(fieldError, other.fieldError, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      disabledFill: Color.lerp(disabledFill, other.disabledFill, t)!,
      disabledInk: Color.lerp(disabledInk, other.disabledInk, t)!,
      glyphSurfaces: t < 0.5 ? glyphSurfaces : other.glyphSurfaces,
      glyphInks: t < 0.5 ? glyphInks : other.glyphInks,
    );
  }
}

/// Radii, collapsed from the old 10 / 14 / 18 / 20 ladder to three steps.
abstract final class Radii {
  /// Chips, glyph plates, small controls.
  static const small = 12.0;

  /// Cards, alerts, fields-in-a-group.
  static const medium = 16.0;

  /// The hero, and anything that frames a whole section.
  static const large = 22.0;

  static BorderRadius get sm => BorderRadius.circular(small);
  static BorderRadius get md => BorderRadius.circular(medium);
  static BorderRadius get lg => BorderRadius.circular(large);
}

/// Type ramp. Every figure is tabular so columns of money line up and a digit
/// change never reflows the row.
abstract final class AppType {
  static const sans = 'InterTight';
  static const mono = 'IBMPlexMono';

  static const _tnum = <FontFeature>[FontFeature.tabularFigures()];

  /// Screen title — "Welcome back", "Reports".
  static const display = TextStyle(
    fontFamily: sans,
    fontSize: 30,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.9,
  );

  /// The splash headline.
  static const displayLarge = TextStyle(
    fontFamily: sans,
    fontSize: 40,
    height: 1.05,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.4,
  );

  /// Greeting, page heading inside a scroll view.
  static const title = TextStyle(
    fontFamily: sans,
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.72,
  );

  /// Card heading — "Where your money sits".
  static const cardTitle = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    height: 1.0,
    fontWeight: FontWeight.w700,
  );

  /// The hero figure.
  static const heroFigure = TextStyle(
    fontFamily: sans,
    fontSize: 44,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.76,
    fontFeatures: _tnum,
  );

  /// The `GHS` that stands beside the hero figure.
  static const heroCode = TextStyle(
    fontFamily: sans,
    fontSize: 16,
    height: 1.0,
    fontWeight: FontWeight.w600,
  );

  /// A figure in a two-up card.
  static const figureLarge = TextStyle(
    fontFamily: sans,
    fontSize: 22,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.66,
    fontFeatures: _tnum,
  );

  /// A figure in a three-up card, and every supporting stat.
  static const figure = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    fontFeatures: _tnum,
  );

  /// A figure on a row — transactions, category totals.
  static const figureRow = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 1.0,
    fontWeight: FontWeight.w700,
    fontFeatures: _tnum,
  );

  /// Row title.
  static const rowTitle = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// Row subtitle — account and time.
  static const rowSub = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );

  /// Body copy inside a card or alert.
  static const body = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w500,
  );

  /// The smaller body — hero caption, helper text.
  static const bodySmall = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w500,
  );

  /// Field label, legend entry.
  static const label = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    height: 1.0,
    fontWeight: FontWeight.w600,
  );

  /// The label above a figure inside a tinted card.
  static const figureLabel = TextStyle(
    fontFamily: sans,
    fontSize: 10,
    height: 1.0,
    fontWeight: FontWeight.w600,
  );

  /// The `GHS` code that sits on its own line above a figure. Putting the code
  /// here is what lets a 114px column hold `-12,480.00` without truncating.
  static const currencyCode = TextStyle(
    fontFamily: sans,
    fontSize: 9,
    height: 1.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.9,
  );

  /// Button text.
  static const button = TextStyle(
    fontFamily: sans,
    fontSize: 16,
    height: 1.0,
    fontWeight: FontWeight.w700,
  );

  /// Mono eyebrow — "NOT COVERED", "SAFE TO SPEND", "WEEK 34".
  static const eyebrow = TextStyle(
    fontFamily: mono,
    fontSize: 10,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
  );

  /// Mono caption sitting beside a heading — "VS AUG", "SHARE OF EXPENSES".
  static const monoCaption = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    height: 1.0,
    fontWeight: FontWeight.w600,
  );

  /// Bottom-nav label.
  static const navLabel = TextStyle(
    fontFamily: sans,
    fontSize: 10,
    height: 1.0,
    fontWeight: FontWeight.w600,
  );
}
