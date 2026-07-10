import '../core/constants/api_constants.dart';
import '../models/badge_model.dart';
import 'api_service.dart';

class BadgeService {
  final ApiService _api = ApiService();

  // QA fix ("Fix BadgeService null response handling"): `response['data']
  // as List<dynamic>` crashed with a type-cast exception whenever data
  // came back null (a server error, an unexpected empty response, etc.) -
  // now falls back to an empty list instead of throwing.
  Future<List<BadgeModel>> fetchMine() async {
    final response = await _api.get(ApiConstants.badgesMine);
    final list = response['data'] as List<dynamic>? ?? [];
    return list.map((json) => BadgeModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<BadgeModel>> fetchForStudent(int studentId) async {
    final response = await _api.get(ApiConstants.badgesForStudent(studentId));
    final list = response['data'] as List<dynamic>? ?? [];
    return list.map((json) => BadgeModel.fromJson(json as Map<String, dynamic>)).toList();
  }
}
