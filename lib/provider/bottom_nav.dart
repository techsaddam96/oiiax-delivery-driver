import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/material.dart';

class BottomNavProvider extends UserScopedNotifier {
  static const List<String> _allShipmentScopes = [
    'instant',
    'scheduled',
    'other',
  ];

  int _selectedIndex = 0;
  String _shipmentsTabScope = 'instant';
  bool _shipmentsOffers = false;
  Widget? _overlayPage;

  @override
  void clearUserState() {
    _selectedIndex = 0;
    _shipmentsTabScope = 'instant';
    _shipmentsOffers = false;
    _overlayPage = null;
  }

  int get selectedIndex => _selectedIndex;
  int get shipmentsTabIndex =>
      _allShipmentScopes.indexOf(_shipmentsTabScope).clamp(0, 2).toInt();
  String get shipmentsTabScope => _shipmentsTabScope;
  bool get shipmentsOffers => _shipmentsOffers;
  Widget? get overlayPage => _overlayPage;

  void setIndex(int index) {
    if (index < 0 || index > 4) return;
    if (_selectedIndex == index && _overlayPage == null) return;

    _selectedIndex = index;
    _overlayPage = null;
    notifyListeners();
  }

  void setShipmentsTab(int index, {bool offers = false}) {
    if (index < 0 || index >= _allShipmentScopes.length) return;
    setShipmentsTabScope(_allShipmentScopes[index], offers: offers);
  }

  void setShipmentsTabScope(String scope, {bool offers = false}) {
    if (!_allShipmentScopes.contains(scope)) return;
    if (_shipmentsTabScope == scope && _shipmentsOffers == offers) return;

    _shipmentsTabScope = scope;
    _shipmentsOffers = offers;
    notifyListeners();
  }

  /// Drops a tab that the latest authenticated policy no longer permits.
  /// Instant is always present, so it is the deterministic safe destination.
  void reconcileShipmentTabScopes(List<String> visibleScopes) {
    if (visibleScopes.isEmpty || visibleScopes.contains(_shipmentsTabScope)) {
      return;
    }

    _shipmentsTabScope = visibleScopes.first;
    _shipmentsOffers = false;
    notifyListeners();
  }

  void showOverlay(Widget page) {
    _overlayPage = page;
    notifyListeners();
  }

  void clearOverlay() {
    _overlayPage = null;
    notifyListeners();
  }
}
