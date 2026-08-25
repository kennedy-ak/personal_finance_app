import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_app/core/category_icons.dart';
import 'package:personal_finance_app/core/constants.dart';
import 'package:personal_finance_app/features/categories/data/category_repository.dart';
import 'package:personal_finance_app/features/categories/domain/category.dart';

Category cat(
  String name, {
  CategoryKind kind = CategoryKind.expense,
  bool hidden = false,
  String? icon,
}) =>
    Category(
      id: name,
      name: name,
      kind: kind,
      icon: icon,
      isHidden: hidden,
      isBuiltin: false,
      sortOrder: 0,
    );

/// Reads a provider with the category list stubbed out, so none of this needs
/// a Supabase connection.
List<String> namesFrom(List<Category> all, Provider<List<String>> provider) {
  final container = ProviderContainer(
    overrides: [
      allCategoriesProvider.overrideWith((_) async => all),
    ],
  );
  addTearDown(container.dispose);
  // The override resolves synchronously enough for the derived provider once
  // the future completes; read it after the microtask drain.
  container.read(allCategoriesProvider);
  return container.read(provider);
}

void main() {
  group('the list the pickers offer', () {
    test('falls back to the built-ins while nothing has loaded', () {
      // Covers both a first frame and a project where migration 0007 has not
      // been run: the user can still file a transaction either way.
      expect(namesFrom(const [], expenseCategoryNamesProvider),
          kExpenseCategories);
      expect(
          namesFrom(const [], incomeCategoryNamesProvider), kIncomeCategories);
    });

    testWidgets('drops hidden categories once the list has loaded',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          allCategoriesProvider.overrideWith((_) async => [
                cat('Tithe'),
                cat('Chop money'),
                cat('Entertainment', hidden: true),
              ]),
        ],
      );
      addTearDown(container.dispose);
      await container.read(allCategoriesProvider.future);

      expect(container.read(expenseCategoryNamesProvider),
          ['Tithe', 'Chop money']);
    });

    testWidgets('keeps the two sides apart', (tester) async {
      final container = ProviderContainer(
        overrides: [
          allCategoriesProvider.overrideWith((_) async => [
                cat('Tithe'),
                cat('Side hustle', kind: CategoryKind.income),
              ]),
        ],
      );
      addTearDown(container.dispose);
      await container.read(allCategoriesProvider.future);

      expect(container.read(expenseCategoryNamesProvider), ['Tithe']);
      expect(container.read(incomeCategoryNamesProvider), ['Side hustle']);
    });

    testWidgets('leaves the picker empty when every category is hidden',
        (tester) async {
      // Not a fallback to the defaults: someone who cleared the list on purpose
      // should not have it handed back to them.
      final container = ProviderContainer(
        overrides: [
          allCategoriesProvider.overrideWith((_) async => [
                cat('Tithe', hidden: true),
              ]),
        ],
      );
      addTearDown(container.dispose);
      await container.read(allCategoriesProvider.future);

      expect(container.read(expenseCategoryNamesProvider), isEmpty);
    });
  });

  group('icons', () {
    testWidgets('a custom category wears the icon it was given',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          allCategoriesProvider.overrideWith((_) async => [
                cat('Chop money', icon: 'fastfood'),
                cat('Tithe'),
              ]),
        ],
      );
      addTearDown(container.dispose);
      await container.read(allCategoriesProvider.future);
      container.read(categoryIconSyncProvider);

      expect(iconForCategory('Chop money'), Icons.fastfood);
      // No icon stored and no built-in match: a neutral label, not the
      // transfer arrows a missing entry used to fall through to.
      expect(iconForCategory('Tithe'), Icons.label_outline);
      // Built-ins still resolve by name.
      expect(iconForCategory('Food & Dining'), Icons.restaurant);
    });
  });
}
