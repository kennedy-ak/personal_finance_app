import 'package:flutter/material.dart';

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
  'Other': Icons.category,
  'Salary': Icons.work,
  'Bonus': Icons.star,
  'Business': Icons.business_center,
  'Investment': Icons.trending_up,
  'Gift': Icons.card_giftcard,
  'Refund': Icons.replay,
  'Transfer': Icons.swap_horiz,
};

IconData iconForCategory(String c) =>
    kCategoryIcons[c] ?? Icons.swap_horiz;
