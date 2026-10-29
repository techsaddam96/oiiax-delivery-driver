// providers/time_provider.dart
import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/material.dart';

class TimeProvider extends UserScopedNotifier {
  final TextEditingController timeController = TextEditingController();

  int selectedHour = 6;
  int selectedMinute = 30;
  String selectedPeriod = 'AM'; // or 'PM'

  @override
  void clearUserState() {
    timeController.clear();
    selectedHour = 6;
    selectedMinute = 30;
    selectedPeriod = 'AM';
  }

  void setHour(int hour) {
    selectedHour = hour;
    notifyListeners();
  }

  void setMinute(int minute) {
    selectedMinute = minute;
    notifyListeners();
  }

  void setPeriod(String period) {
    selectedPeriod = period;
    notifyListeners();
  }

  void resetTime() {
    timeController.clear();
    selectedHour = 11;

    notifyListeners();
  }

  String get formattedTime =>
      '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')} $selectedPeriod';
}
