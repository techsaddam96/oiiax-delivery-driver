// // provider/wallet.dart
//
// class WalletProvider with ChangeNotifier {
//   int _selectedTabIndex = -1; // -1 means no tab selected (show wallet content)

//   int get selectedTabIndex => _selectedTabIndex;

//   void setSelectedTab(int index) {
//     _selectedTabIndex = index;
//     notifyListeners();
//   }

//   void resetToWallet() {
//     _selectedTabIndex = -1;
//     notifyListeners();
//   }
// }

import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/material.dart';

class WalletProvider extends UserScopedNotifier {
  @override
  void clearUserState() {
    _selectedTabIndex = -1;
  }

  int _selectedTabIndex = -1; // -1 means no tab selected (show wallet content)

  int get selectedTabIndex => _selectedTabIndex;

  void setSelectedTab(int index) {
    _selectedTabIndex = index;
    notifyListeners();
  }

  void resetTab() {
    _selectedTabIndex = -1;
    notifyListeners();
  }

  void resetToWallet() {
    _selectedTabIndex = -1;
    notifyListeners();
  }
}
