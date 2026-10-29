import '../../services/statement_handover_service.dart';
import '../../services/user_session_state.dart';

class StatementHandoversProvider extends UserScopedNotifier {
  StatementHandoversProvider({StatementHandoverService? service})
    : _service = service ?? StatementHandoverService();
  final StatementHandoverService _service;
  List<CashHandover> _items = [];
  List<CashHandover> get items => List.unmodifiable(_items);
  bool loading = false;
  bool submitting = false;
  bool hasMore = false;
  String? error;
  int _page = 0;
  int _listRequest = 0;
  @override
  void clearUserState() {
    _listRequest++;
    _items = [];
    _page = 0;
    loading = submitting = hasMore = false;
    error = null;
  }

  Future<void> load({bool more = false}) async {
    if (loading || submitting || (more && !hasMore)) return;
    final generation = stateGeneration;
    final request = ++_listRequest;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = more ? _page + 1 : 1;
      final result = await guardSession(_service.fetch(page), generation);
      if (request != _listRequest) return;
      _items = more ? [..._items, ...result.items] : result.items;
      hasMore = result.hasMore;
      _page = page;
    } on SessionChanged {
      return;
    } catch (_) {
      if (acceptsState(generation)) error = 'SERVER_ERROR';
    } finally {
      if (acceptsState(generation) && request == _listRequest) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> complete(int id, String code) async {
    if (submitting) throw const HandoverException('BUSY');
    final generation = stateGeneration;
    submitting = true;
    ++_listRequest; // A pending list must not restore a completed row.
    loading = false;
    notifyListeners();
    try {
      await guardSession(_service.complete(id, code), generation);
      _items = _items.where((item) => item.id != id).toList();
    } finally {
      if (acceptsState(generation)) {
        submitting = false;
        notifyListeners();
      }
    }
  }
}
