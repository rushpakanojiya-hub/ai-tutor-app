import 'package:flutter/material.dart';
import '../models/subject_model.dart';
import '../services/api_service.dart';
import '../services/subject_service.dart';

/// Holds subject list state (loading/error/data) for SubjectsScreen.
class SubjectProvider extends ChangeNotifier {
  final SubjectService _service = SubjectService();

  List<SubjectModel> subjects = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadSubjects(int categoryId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      subjects = await _service.fetchSubjectsByCategory(categoryId);
    } on ApiException catch (e) {
      errorMessage = e.message;
    } catch (e) {
      errorMessage = 'Something went wrong. Please try again.';
    }

    isLoading = false;
    notifyListeners();
  }
}
