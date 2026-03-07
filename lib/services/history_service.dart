import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/muscle_data.dart';

/// Service for managing local muscle evaluation history.
class HistoryService {
  static const String _storageKey = 'muscle_evaluation_history';

  /// Save the entire list of evaluations to local storage.
  static Future<void> saveEvaluations(List<MuscleEvaluation> evaluations) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = evaluations.map((e) => e.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await prefs.setString(_storageKey, jsonString);
  }

  /// Load evaluations from local storage.
  static Future<List<MuscleEvaluation>> loadEvaluations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((item) => MuscleEvaluation.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading history: $e');
      return [];
    }
  }

  /// Add a single evaluation to the local history.
  static Future<void> addEvaluation(MuscleEvaluation evaluation) async {
    final current = await loadEvaluations();
    current.add(evaluation);
    await saveEvaluations(current);
  }

  /// Delete a single evaluation from the local history.
  static Future<void> deleteEvaluation(int index) async {
    final current = await loadEvaluations();
    if (index >= 0 && index < current.length) {
      current.removeAt(index);
      await saveEvaluations(current);
    }
  }
}
