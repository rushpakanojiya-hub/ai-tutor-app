import '../core/constants/api_constants.dart';
import '../models/notification_model.dart';
import 'api_service.dart';

class NotificationService {
  final ApiService _api = ApiService();

  Future<List<NotificationModel>> fetchAll() async {
    final response = await _api.get(ApiConstants.notifications);
    final data = response['data'] as List<dynamic>? ?? [];
    return data.map((json) => NotificationModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<int> fetchUnreadCount() async {
    final response = await _api.get(ApiConstants.notificationUnreadCount);
    return (response['data'] as Map<String, dynamic>)['unread_count'] as int? ?? 0;
  }

  Future<void> markRead(int id) async => _api.post(ApiConstants.notificationRead(id), {});
  Future<void> markAllRead() async => _api.post(ApiConstants.notificationReadAll, {});
}
