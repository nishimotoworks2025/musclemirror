import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/muscle_data.dart';

class EvaluationModeService extends ChangeNotifier {
  static final EvaluationModeService _instance =
      EvaluationModeService._internal();
  factory EvaluationModeService() => _instance;
  EvaluationModeService._internal();

  static const String _storageKey = 'evaluationType';

  EvaluationType _currentType = EvaluationType.balanced;
  EvaluationType get currentType => _currentType;

  Future<EvaluationType> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final loadedType = EvaluationType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => EvaluationType.balanced,
    );
    _currentType = _normalize(loadedType);
    notifyListeners();
    return _currentType;
  }

  Future<void> save(EvaluationType type) async {
    final normalized = _normalize(type);
    if (_currentType == normalized) {
      return;
    }
    _currentType = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, normalized.name);
  }

  EvaluationType _normalize(EvaluationType type) {
    if (type != EvaluationType.balanced &&
        type != EvaluationType.physique) {
      return EvaluationType.balanced;
    }
    return type;
  }
}
