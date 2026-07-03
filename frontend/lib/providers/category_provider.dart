import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../services/api_service.dart';
import '../services/category_service.dart';

/// Holds category list state (loading/error/data) for CategoriesScreen.
class CategoryProvider extends ChangeNotifier {
  final CategoryService _service = CategoryService();

  List<CategoryModel> categories = [];
  bool isLoading = false;
  String? errorMessage;

  /// Client-side filter for the search box on CategoriesScreen â€” Day 2's
  /// dedicated global search (Feature 6) lives in SearchProvider instead;
  /// this is just a quick in-page filter over already-loaded categories.
  String searchQuery = '';

  List<CategoryModel> get filteredCategories {
    if (searchQuery.isEmpty) return categories;
    return categories
        .where((c) => c.name.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }

  Future<void> loadCategories() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      categories = await _service.fetchCategories();
    } on ApiException catch (e) {
      errorMessage = e.message;
    } catch (e) {
      errorMessage = 'Something went wrong. Please try again.';
    }

    isLoading = false;
    notifyListeners();
  }

  void updateSearchQuery(String query) {
    searchQuery = query;
    notifyListeners();
  }
}
