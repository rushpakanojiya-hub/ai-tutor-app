import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/search_service.dart';

/// Holds search state (query, results, loading/error) plus a simple
/// in-memory search history for SearchScreen.
class SearchProvider extends ChangeNotifier {
  final SearchService _service = SearchService();

  SearchResults? results;
  bool isLoading = false;
  String? errorMessage;
  List<String> history = [];

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      results = null;
      notifyListeners();
      return;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      results = await _service.search(query.trim());
      _addToHistory(query.trim());
    } on ApiException catch (e) {
      errorMessage = e.message;
    } catch (e) {
      errorMessage = 'Search failed. Please try again.';
    }

    isLoading = false;
    notifyListeners();
  }

  void _addToHistory(String query) {
    history.remove(query);
    history.insert(0, query);
    if (history.length > 10) {
      history = history.sublist(0, 10);
    }
  }

  void clearHistory() {
    history = [];
    notifyListeners();
  }

  void clearResults() {
    results = null;
    notifyListeners();
  }
}
