import '../entities/recipe_amount.dart';
import '../entities/recipe_inputs.dart';

abstract final class RecipeValidation {
  static String? quantity(String? text) {
    if (text == null || text.trim().isEmpty) return 'Vui lòng nhập định lượng.';
    try {
      RecipeQuantity.parse(text);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  static String? wastePercent(String? text) {
    try {
      RecipeWastePercent.parseOrZero(text);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  static Map<String, String> input(RecipeInput input) {
    final errors = <String, String>{};
    if (input.ingredients.isEmpty || input.ingredients.length > 100) {
      errors['ingredients'] = 'Công thức cần từ 1 đến 100 nguyên liệu.';
    }
    final seen = <String>{};
    for (var index = 0; index < input.ingredients.length; index++) {
      final id = input.ingredients[index].ingredientId.trim();
      if (id.isEmpty) {
        errors['ingredients[$index].ingredientId'] =
            'Vui lòng chọn nguyên liệu.';
      } else if (!seen.add(id)) {
        errors['ingredients[$index].ingredientId'] =
            'Nguyên liệu đã có trong công thức.';
      }
    }
    if (input is CreateRecipeVersionInput && input.expectedVersion < 0) {
      errors['expectedVersion'] =
          'Phiên bản dữ liệu không hợp lệ. Vui lòng tải lại.';
    }
    return errors;
  }
}
