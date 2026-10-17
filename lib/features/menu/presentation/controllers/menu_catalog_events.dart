import 'package:flutter/foundation.dart';

/// Scoped to the current account/tenant. No entity data or drafts are stored here.
class MenuCatalogEvents extends ChangeNotifier {
  int groupRevision = 0;
  int itemRevision = 0;
  int ingredientRevision = 0;
  int recipeRevision = 0;
  String? deletedGroupId;
  String? changedItemId;
  String? changedIngredientId;
  String? changedRecipeMenuItemId;

  void groupsChanged({String? deletedId}) {
    groupRevision++;
    deletedGroupId = deletedId;
    notifyListeners();
  }

  void itemChanged(String? id) {
    itemRevision++;
    changedItemId = id;
    notifyListeners();
  }

  void ingredientChanged([String? id]) {
    ingredientRevision++;
    changedIngredientId = id;
    notifyListeners();
  }

  void recipeChanged(String menuItemId) {
    recipeRevision++;
    changedRecipeMenuItemId = menuItemId;
    notifyListeners();
  }
}
