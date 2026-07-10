import '../core/constants/api_constants.dart';
import '../models/category_model.dart';
import '../models/lesson_model.dart';
import '../models/subject_model.dart';
import 'api_service.dart';

/// Result bundle from GET /api/search?q=..., sectioned exactly like the
/// backend's search.Results struct.
class SearchResults {
  final List<CategoryModel> categories;
  final List<SubjectModel> subjects;
  final List<LessonModel> lessons;
  SearchResults({required this.categories, required this.subjects, required this.lessons});
  bool get isEmpty => categories.isEmpty && subjects.isEmpty && lessons.isEmpty;
}

/// Talks to the backend's /api/search endpoint.
class SearchService {
  final ApiService _api = ApiService();

  Future<SearchResults> search(String query) async {
    // QA fix ("Fix SearchService URL encoding"): the raw query string was
    // interpolated straight into the URL - spaces, "&", "#", "+", or any
    // non-ASCII text could break the query-string parsing or silently
    // search for the wrong thing. Uri.encodeQueryComponent makes this
    // safe for any input.
    final encodedQuery = Uri.encodeQueryComponent(query);
    final response = await _api.get('${ApiConstants.search}?q=$encodedQuery');
    final data = response['data'] as Map<String, dynamic>? ?? {};
    final categories = (data['categories'] as List<dynamic>? ?? [])
        .map((json) => CategoryModel.fromJson(json as Map<String, dynamic>))
        .toList();
    final subjects = (data['subjects'] as List<dynamic>? ?? [])
        .map((json) => SubjectModel.fromJson(json as Map<String, dynamic>))
        .toList();
    final lessons = (data['lessons'] as List<dynamic>? ?? [])
        .map((json) => LessonModel.fromJson(json as Map<String, dynamic>))
        .toList();
    return SearchResults(categories: categories, subjects: subjects, lessons: lessons);
  }
}
