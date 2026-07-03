import '../core/constants/api_constants.dart';
import '../models/category_model.dart';
import 'api_service.dart';

/// Talks to the backend's /api/categories endpoints.
class CategoryService {
  final ApiService _api = ApiService();

  Future<List<CategoryModel>> fetchCategories() async {
    final response = await _api.get(ApiConstants.categories);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => CategoryModel.fromJson(json as Map<String, dynamic>)).toList();
  }
}
