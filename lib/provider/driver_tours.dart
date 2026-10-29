import 'package:blockatie/models/driver_tour.dart';
import 'package:blockatie/services/driver_tour_service.dart';
import 'package:blockatie/services/user_session_state.dart';

/// Session-scoped read state for the Driver Tours screens.
///
/// No lifecycle state is changed optimistically: an accepted command is always
/// followed by authoritative details/current reads. A refresh happens when the
/// page is opened, pulled, or resumed — never as a background polling loop.
class DriverToursProvider extends UserScopedNotifier {
  DriverToursProvider({DriverToursRepository? repository})
    : _repository = repository ?? DriverTourService();

  final DriverToursRepository _repository;

  List<DriverTour> _tours = const [];
  DriverTourDetails? _details;
  DriverTourException? _currentError;
  DriverTourException? _detailsError;
  bool _loadingCurrent = false;
  bool _loadingDetails = false;
  int? _selectedTourId;
  int? _commandTourId;
  int _currentRequest = 0;
  int _detailsRequest = 0;

  List<DriverTour> get tours => List.unmodifiable(_tours);
  DriverTourDetails? get details => _details;
  DriverTourException? get currentError => _currentError;
  DriverTourException? get detailsError => _detailsError;
  bool get isLoadingCurrent => _loadingCurrent;
  bool get isLoadingDetails => _loadingDetails;
  int? get selectedTourId => _selectedTourId;
  bool get hasActiveCommand => _commandTourId != null;
  bool isCommandBusy(int tourId) => _commandTourId == tourId;

  @override
  void clearUserState() {
    _currentRequest++;
    _detailsRequest++;
    _tours = const [];
    _details = null;
    _currentError = null;
    _detailsError = null;
    _loadingCurrent = false;
    _loadingDetails = false;
    _selectedTourId = null;
    _commandTourId = null;
  }

  Future<void> loadCurrent({bool selectFirst = true}) async {
    if (_loadingCurrent) return;
    final generation = stateGeneration;
    final request = ++_currentRequest;
    _loadingCurrent = true;
    _currentError = null;
    notifyListeners();

    try {
      final tours = await guardSession(_repository.current(), generation);
      if (!acceptsState(generation) || request != _currentRequest) return;
      _tours = tours;
      _currentError = null;

      final stillSelected = tours.any((tour) => tour.id == _selectedTourId);
      if (!stillSelected && selectFirst) {
        _selectedTourId = tours.isEmpty ? null : tours.first.id;
      }
    } on SessionChanged {
      return;
    } on DriverTourException catch (error) {
      if (acceptsState(generation) && request == _currentRequest) {
        _currentError = error;
      }
    } catch (_) {
      if (acceptsState(generation) && request == _currentRequest) {
        _currentError = const DriverTourException(
          kind: DriverTourFailureKind.unavailable,
          code: 'TOUR_SERVICE_UNAVAILABLE',
          isRetryable: true,
        );
      }
    } finally {
      if (acceptsState(generation) && request == _currentRequest) {
        _loadingCurrent = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectTour(int tourId) async {
    if (tourId <= 0) return;
    _selectedTourId = tourId;
    _detailsError = null;
    notifyListeners();
    await loadDetails(tourId);
  }

  Future<void> loadDetails(int tourId) async {
    if (tourId <= 0 || _loadingDetails) return;
    final generation = stateGeneration;
    final request = ++_detailsRequest;
    _loadingDetails = true;
    _detailsError = null;
    notifyListeners();
    try {
      final details = await guardSession(
        _repository.details(tourId),
        generation,
      );
      if (!acceptsState(generation) || request != _detailsRequest) return;
      _details = details;
      _selectedTourId = details.tour.id;
      _detailsError = null;
    } on SessionChanged {
      return;
    } on DriverTourException catch (error) {
      if (acceptsState(generation) && request == _detailsRequest) {
        _detailsError = error;
      }
    } catch (_) {
      if (acceptsState(generation) && request == _detailsRequest) {
        _detailsError = const DriverTourException(
          kind: DriverTourFailureKind.unavailable,
          code: 'TOUR_SERVICE_UNAVAILABLE',
          isRetryable: true,
        );
      }
    } finally {
      if (acceptsState(generation) && request == _detailsRequest) {
        _loadingDetails = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final generation = stateGeneration;
    final selected = _selectedTourId;
    await loadCurrent(selectFirst: selected == null);
    if (!acceptsState(generation)) return;
    final target = _selectedTourId ?? selected;
    if (target != null) await loadDetails(target);
  }

  /// Executes one server-confirmed lifecycle command.
  ///
  /// The provider deliberately does not amend [details] from the response. It
  /// waits for the canonical read model instead, including after an idempotent
  /// retry. A 409 triggers a read before the exception reaches the UI so the
  /// driver can review the actual state rather than re-submit stale data.
  Future<DriverTourCommandResult> command({
    required String action,
    required DriverTour tour,
    String? reason,
  }) async {
    if (_commandTourId != null) {
      throw const DriverTourException(
        kind: DriverTourFailureKind.conflict,
        code: 'TOUR_COMMAND_IN_PROGRESS',
      );
    }
    final generation = stateGeneration;
    _commandTourId = tour.id;
    notifyListeners();
    try {
      final result = await guardSession(
        _repository.command(
          action: action,
          tourId: tour.id,
          expectedStateVersion: tour.stateVersion,
          reason: reason,
        ),
        generation,
      );
      // Both reads are authoritative. A completed tour is correctly absent
      // from `current`, while details remains readable as the command receipt.
      await Future.wait<void>([
        loadCurrent(selectFirst: false),
        loadDetails(tour.id),
      ]);
      if (!acceptsState(generation)) throw const SessionChanged();
      return result;
    } on DriverTourException catch (error) {
      if (error.kind == DriverTourFailureKind.conflict &&
          acceptsState(generation)) {
        await loadDetails(tour.id);
      }
      rethrow;
    } finally {
      if (acceptsState(generation)) {
        _commandTourId = null;
        notifyListeners();
      }
    }
  }
}
