import '../core/constants/api_constants.dart';
import '../models/xp_model.dart';
import 'api_service.dart';

class XPService {
  final ApiService _api = ApiService();

  Future<XPSummary> fetchMine() async {
    final response = await _api.get(ApiConstants.xpMine);
    return XPSummary.fromJson(response['data'] as Map<String, dynamic>);
  }
}
