import 'package:flutter/material.dart';

/// Icons a user may attach to a category they made.
///
/// Keyed by slug rather than codepoint: the slug is what goes in the database,
/// so a Material renumbering can never turn someone's Tithe icon into a
/// parking meter, and the icon font still tree-shakes.
const Map<String, IconData> kPickableIcons = {
  'restaurant': Icons.restaurant,
  'coffee': Icons.local_cafe,
  'fastfood': Icons.fastfood,
  'grocery': Icons.local_grocery_store,
  'bus': Icons.directions_bus,
  'car': Icons.directions_car,
  'taxi': Icons.local_taxi,
  'fuel': Icons.local_gas_station,
  'flight': Icons.flight,
  'home': Icons.home,
  'bolt': Icons.bolt,
  'water': Icons.water_drop,
  'wifi': Icons.wifi,
  'phone': Icons.phone_android,
  'tv': Icons.tv,
  'shopping': Icons.shopping_bag,
  'clothes': Icons.checkroom,
  'movie': Icons.movie,
  'music': Icons.music_note,
  'game': Icons.sports_esports,
  'sports': Icons.sports_soccer,
  'fitness': Icons.fitness_center,
  'medical': Icons.medical_services,
  'pharmacy': Icons.local_pharmacy,
  'school': Icons.school,
  'book': Icons.menu_book,
  'child': Icons.child_care,
  'family': Icons.family_restroom,
  'pets': Icons.pets,
  'spa': Icons.spa,
  'cut': Icons.content_cut,
  'church': Icons.volunteer_activism,
  'gift': Icons.card_giftcard,
  'shield': Icons.shield,
  'receipt': Icons.receipt_long,
  'build': Icons.build,
  'savings': Icons.savings,
  'cash': Icons.payments,
  'card': Icons.credit_card,
  'bank': Icons.account_balance,
  'work': Icons.work,
  'business': Icons.business_center,
  'trending_up': Icons.trending_up,
  'star': Icons.star,
  'replay': Icons.replay,
  'swap': Icons.swap_horiz,
  'category': Icons.category,
  'label': Icons.label_outline,
};

/// The built-in names, for anyone whose categories have not loaded yet.
const Map<String, IconData> kCategoryIcons = {
  'Food': Icons.restaurant,
  'Food & Dining': Icons.restaurant,
  'Transport': Icons.directions_bus,
  'Transportation': Icons.directions_bus,
  'Housing': Icons.home,
  'Utilities': Icons.bolt,
  'Bills & Utilities': Icons.bolt,
  'Entertainment': Icons.movie,
  'Healthcare': Icons.medical_services,
  'Education': Icons.school,
  'Shopping': Icons.shopping_bag,
  'Personal Care': Icons.spa,
  'Travel': Icons.flight,
  'Insurance': Icons.shield,
  'Gifts & Donations': Icons.card_giftcard,
  'Bank Charges': Icons.receipt_long,
  'Other': Icons.category,
  'Salary': Icons.work,
  'Bonus': Icons.star,
  'Business': Icons.business_center,
  'Investment': Icons.trending_up,
  'Gift': Icons.card_giftcard,
  'Refund': Icons.replay,
  'Transfer': Icons.swap_horiz,
};

/// Icons for the categories the user actually has, refreshed whenever the
/// category list loads.
///
/// A plain map rather than a provider because the callers — transaction rows,
/// chart legends — are handed a category *name* and nothing else. Threading a
/// ref through every one of them to render a 16px glyph is not worth it.
final Map<String, String> _userIconKeys = {};

void registerCategoryIcons(Map<String, String> byName) {
  _userIconKeys
    ..clear()
    ..addAll(byName);
}

IconData iconForKey(String? key) =>
    key == null ? Icons.label_outline : (kPickableIcons[key] ?? Icons.label_outline);

IconData iconForCategory(String c) {
  final key = _userIconKeys[c];
  if (key != null) return kPickableIcons[key] ?? Icons.label_outline;
  return kCategoryIcons[c] ?? Icons.label_outline;
}
