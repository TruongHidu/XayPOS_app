enum ItemType {
  menuItem('MENU_ITEM', 'Món bán'),
  ingredient('INGREDIENT', 'Nguyên liệu');

  const ItemType(this.code, this.label);
  final String code;
  final String label;

  static ItemType fromCode(String code) => switch (code) {
    'MENU_ITEM' => menuItem,
    'INGREDIENT' => ingredient,
    _ => throw FormatException('Unknown itemType code: $code'),
  };
}
