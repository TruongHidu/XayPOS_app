/// How accepting a menu item affects stock. The API only reports this value;
/// requests configure it through `trackInventory` and `recipeEnabled`.
enum InventoryMode {
  none('NONE'),
  direct('DIRECT'),
  recipe('RECIPE');

  const InventoryMode(this.code);
  final String code;
}
