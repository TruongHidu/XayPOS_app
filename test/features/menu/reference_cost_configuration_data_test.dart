import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/features/menu/data/dto/ingredient_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/ingredient_requests.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_requests.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/menu/domain/validation/ingredient_validation.dart';
import 'package:pos_saas_app/features/menu/domain/validation/menu_validation.dart';
import 'ingredient_fakes.dart';
import 'menu_fakes.dart';

void main() {
  test(
    'catalogue flags come from REST, including false and explicitly configured zero',
    () {
      final unknown = MenuItemDto.fromJson(
        itemJson()..['costPrice'] = 0,
      ).toEntity();
      expect(unknown.costConfigured, false);
      expect(unknown.recipeEnabled, false);
      final confirmed = MenuItemDto.fromJson(
        itemJson(costConfigured: true, recipeEnabled: true)..['costPrice'] = 0,
      ).toEntity();
      expect(confirmed.costConfigured, true);
      expect(confirmed.recipeEnabled, true);
      expect(confirmed.costPrice, MenuPrice.zero);
      final ingredient = IngredientDto.fromJson(
        ingredientJson(costConfigured: false)..['costPrice'] = 0,
      ).toEntity();
      expect(ingredient.costConfigured, false);
      for (final field in ['costConfigured', 'recipeEnabled']) {
        for (final malformed in [null, 'false', 0]) {
          expect(
            () => MenuItemDto.fromJson(itemJson()..[field] = malformed),
            throwsFormatException,
          );
        }
      }
      for (final malformed in [null, 'true', 1]) {
        expect(
          () => IngredientDto.fromJson(
            ingredientJson()..['costConfigured'] = malformed,
          ),
          throwsFormatException,
        );
      }
      expect(
        () =>
            IngredientDto.fromJson(ingredientJson()..remove('costConfigured')),
        throwsFormatException,
      );
    },
  );

  test('create omission and explicit zero are different JSON requests', () {
    final menu = MenuRequests.createItem(
      const CreateMenuItemInput(
        name: 'Món',
        baseUnit: 'tô',
        salePrice: MenuPrice.zero,
      ),
    );
    final ingredient = IngredientRequests.create(
      const CreateIngredientInput(name: 'NL', baseUnit: 'g'),
    );
    for (final body in [menu, ingredient]) {
      expect(body.containsKey('costPrice'), false);
      expect(body.containsKey('costConfigured'), false);
    }
    expect(menu['recipeEnabled'], false);
    final explicitMenu = MenuRequests.createItem(
      const CreateMenuItemInput(
        name: 'Món',
        baseUnit: 'tô',
        salePrice: MenuPrice.zero,
        costPrice: MenuPrice.zero,
      ),
    );
    final explicitIngredient = IngredientRequests.create(
      const CreateIngredientInput(
        name: 'NL',
        baseUnit: 'g',
        costPrice: MenuPrice.zero,
      ),
    );
    for (final body in [explicitMenu, explicitIngredient]) {
      expect(body.containsKey('costPrice'), true);
      expect(body['costPrice'], 0);
    }
  });

  test(
    'flag-only confirm/clear and toggle-only PATCH retain false, absence and resource version',
    () {
      for (final flag in [true, false]) {
        final menu = UpdateMenuItemInput(
          expectedVersion: 17,
          costConfigured: flag,
        );
        final ingredient = UpdateIngredientInput(
          expectedVersion: 23,
          costConfigured: flag,
        );
        expect(menu.isEmpty, false);
        expect(ingredient.isEmpty, false);
        expect(MenuRequests.updateItem(menu), {
          'expectedVersion': 17,
          'costConfigured': flag,
        });
        expect(IngredientRequests.update(ingredient), {
          'expectedVersion': 23,
          'costConfigured': flag,
        });
        expect(MenuValidation.itemPatch(menu), isEmpty);
        expect(IngredientValidation.patch(ingredient), isEmpty);
      }
      final toggle = const UpdateMenuItemInput(
        expectedVersion: 25,
        recipeEnabled: false,
      );
      expect(toggle.isEmpty, false);
      expect(MenuRequests.updateItem(toggle), {
        'expectedVersion': 25,
        'recipeEnabled': false,
      });
      final enabled = const UpdateMenuItemInput(
        expectedVersion: 26,
        recipeEnabled: true,
      );
      expect(MenuValidation.itemPatch(enabled), isEmpty);
    },
  );

  test(
    'metadata-only changes preserve both stored cost fields and application',
    () {
      final baseline = MenuItemDto.fromJson(
        itemJson(recipeEnabled: true, costConfigured: true)
          ..['costPrice'] = 12500,
      ).toEntity();
      final menu = UpdateMenuItemInput.changes(
        baseline,
        name: 'Mới',
        baseUnit: baseline.baseUnit,
        salePrice: baseline.salePrice,
        sku: baseline.sku!,
        description: '',
        imageUrl: '',
      );
      expect(MenuRequests.updateItem(menu), {
        'name': 'Mới',
        'expectedVersion': baseline.version,
      });
      final initialIngredient = ingredient();
      final renamed = UpdateIngredientInput.changes(
        initialIngredient,
        name: 'Mới',
        baseUnit: initialIngredient.baseUnit,
        sku: initialIngredient.sku!,
        description: initialIngredient.description!,
        trackInventory: initialIngredient.trackInventory,
      );
      expect(IngredientRequests.update(renamed), {
        'name': 'Mới',
        'expectedVersion': initialIngredient.version,
      });
    },
  );

  test(
    'changes keeps explicit equal zero confirmation intent without requiring numeric change',
    () {
      final baseline = MenuItemDto.fromJson(
        itemJson()..['costPrice'] = 0,
      ).toEntity();
      final menu = UpdateMenuItemInput.changes(
        baseline,
        name: baseline.name,
        baseUnit: baseline.baseUnit,
        salePrice: baseline.salePrice,
        sku: baseline.sku!,
        description: '',
        imageUrl: '',
        costConfigured: true,
      );
      expect(MenuRequests.updateItem(menu), {
        'expectedVersion': baseline.version,
        'costConfigured': true,
      });
      final explicitPrice = UpdateMenuItemInput.changes(
        baseline,
        name: baseline.name,
        baseUnit: baseline.baseUnit,
        salePrice: baseline.salePrice,
        sku: baseline.sku!,
        description: '',
        imageUrl: '',
        costPrice: MenuPrice.zero,
      );
      expect(MenuRequests.updateItem(explicitPrice), {
        'expectedVersion': baseline.version,
        'costPrice': 0,
      });
      final source = IngredientDto.fromJson(
        ingredientJson(costConfigured: false)..['costPrice'] = 0,
      ).toEntity();
      final ingredient = UpdateIngredientInput.changes(
        source,
        name: source.name,
        baseUnit: source.baseUnit,
        sku: source.sku!,
        description: source.description!,
        trackInventory: source.trackInventory,
        costPrice: MenuPrice.zero,
      );
      expect(IngredientRequests.update(ingredient), {
        'expectedVersion': source.version,
        'costPrice': 0,
      });
    },
  );

  test(
    'validation enforces create confirmation and clear-price combinations',
    () {
      expect(
        MenuValidation.item(
          const CreateMenuItemInput(
            name: 'Món',
            baseUnit: 'tô',
            salePrice: MenuPrice.zero,
            costConfigured: true,
          ),
        ),
        contains('costPrice'),
      );
      expect(
        IngredientValidation.create(
          const CreateIngredientInput(
            name: 'NL',
            baseUnit: 'g',
            costConfigured: true,
          ),
        ),
        contains('costPrice'),
      );
      final positive = MenuPrice.parse('100');
      expect(
        MenuValidation.itemPatch(
          UpdateMenuItemInput(
            expectedVersion: 1,
            costConfigured: false,
            costPrice: positive,
          ),
        ),
        contains('costPrice'),
      );
      expect(
        IngredientValidation.patch(
          UpdateIngredientInput(
            expectedVersion: 1,
            costConfigured: false,
            costPrice: positive,
          ),
        ),
        contains('costPrice'),
      );
      expect(
        MenuValidation.itemPatch(
          const UpdateMenuItemInput(
            expectedVersion: 1,
            costConfigured: false,
            costPrice: MenuPrice.zero,
          ),
        ),
        isEmpty,
      );
      expect(
        IngredientValidation.create(
          const CreateIngredientInput(
            name: 'NL',
            baseUnit: 'g',
            costConfigured: true,
            costPrice: MenuPrice.zero,
          ),
        ),
        isEmpty,
      );
      expect(
        MenuValidation.item(
          const CreateMenuItemInput(
            name: 'Món',
            baseUnit: 'tô',
            salePrice: MenuPrice.zero,
            recipeEnabled: true,
          ),
        ),
        contains('recipeEnabled'),
      );
    },
  );
}
