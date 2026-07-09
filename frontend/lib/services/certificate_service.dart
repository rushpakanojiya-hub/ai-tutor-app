import '../core/constants/api_constants.dart';
import '../models/certificate_model.dart';
import 'api_service.dart';

class CertificateService {
  final ApiService _api = ApiService();

  Future<List<CertificateModel>> fetchMine() async {
    final response = await _api.get(ApiConstants.certificatesMine);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => CertificateModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<CertificateModel>> fetchForTeacher() async {
    final response = await _api.get(ApiConstants.certificatesTeacher);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => CertificateModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<CertificateModel>> fetchAllForAdmin() async {
    final response = await _api.get(ApiConstants.certificatesAll);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => CertificateModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<CertificateModel> fetchById(int id) async {
    final response = await _api.get(ApiConstants.certificate(id));
    return CertificateModel.fromJson(response['data'] as Map<String, dynamic>);
  }
}
