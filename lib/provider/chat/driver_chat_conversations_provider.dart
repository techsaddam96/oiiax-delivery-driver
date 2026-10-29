import 'dart:async';
import 'dart:collection';

import 'package:blockatie/models/chat/chat_exception.dart';
import 'package:blockatie/models/chat/driver_chat_conversation.dart';
import 'package:blockatie/models/chat/driver_chat_message.dart';
import 'package:blockatie/models/chat/driver_chat_pagination.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum DriverChatConversationsState {
  initial,
  loading,
  loaded,
  refreshing,
  empty,
  error,
}

/// The Driver's conversation list and the global unread badge figure.
///
/// This is the single owner of both. The conversations screen and the floating
/// chat bubble share this one instance rather than each holding a copy, which
/// is why it is registered once in the provider tree.
///
/// It also owns the one app-wide unread poller. Nothing else may run a timer
/// for the badge: [startUnreadPolling] refuses to create a second one, so
/// however many widgets ask, there is exactly one.
///
/// Session safety works on two levels, and both must pass before any field is
/// mutated:
///   * [stateGeneration] from [UserScopedNotifier] — a response issued under a
///     previous driver is discarded instead of being written into the next
///     driver's state;
///   * a local request generation — a response for a page the driver has
///     already navigated away from is discarded too.
class DriverChatConversationsProvider extends UserScopedNotifier {
  DriverChatConversationsProvider({
    required DriverChatRepository repository,
    this.pageSize = 15,
    this.unreadPollingInterval = const Duration(seconds: 15),
  }) : _repository = repository;

  final DriverChatRepository _repository;
  final int pageSize;

  /// How often the badge is re-read while the app is in the foreground. Matches
  /// the thread poller, so chat refreshes at one rhythm.
  final Duration unreadPollingInterval;

  final List<DriverChatConversation> _conversations =
      <DriverChatConversation>[];
  DriverChatConversationsState _state = DriverChatConversationsState.initial;
  DriverChatPagination _pagination = DriverChatPagination.empty;
  int _unreadCount = 0;
  String? _errorMessage;
  DateTime? _lastLoadedAt;

  CancelToken? _requestToken;
  CancelToken? _unreadToken;

  /// One per in-flight shipment resolution. Several shipment screens can be
  /// open at once, so these are tracked as a set rather than a single token.
  final Set<CancelToken> _resolveTokens = <CancelToken>{};
  int _requestGeneration = 0;
  bool _unreadRequestInFlight = false;

  Timer? _unreadTimer;
  bool _unreadPollingRequested = false;
  bool _unreadPollingPaused = false;

  UnmodifiableListView<DriverChatConversation> get conversations =>
      UnmodifiableListView(_conversations);
  DriverChatConversationsState get state => _state;
  DriverChatPagination get pagination => _pagination;
  int get page => _pagination.page;
  int get totalPages => _pagination.totalPages;
  int get total => _pagination.total;
  bool get hasNextPage => _pagination.hasNextPage;
  bool get hasPreviousPage => _pagination.hasPreviousPage;
  int get unreadCount => _unreadCount;

  /// The same figure as [unreadCount], under the name the app shell uses for
  /// it. One field, two readings — the badge and the list never disagree.
  int get globalUnreadCount => _unreadCount;

  /// True only while a timer is actually scheduled, not merely wanted.
  bool get isPollingUnread => _unreadTimer != null;
  bool get isUnreadPollingPaused => _unreadPollingPaused;

  String? get errorMessage => _errorMessage;
  DateTime? get lastLoadedAt => _lastLoadedAt;
  bool get isLoading => _state == DriverChatConversationsState.loading;
  bool get isRefreshing => _state == DriverChatConversationsState.refreshing;
  bool get isBusy => isLoading || isRefreshing;

  /// First load. Does nothing once data is present — use [refresh] to reload.
  Future<void> loadInitial() async {
    if (isBusy || _conversations.isNotEmpty) {
      return;
    }
    await _loadPage(1, DriverChatConversationsState.loading);
  }

  /// Reloads the current page, leaving the driver where they are.
  Future<void> refresh() => _loadPage(
    _pagination.page <= 0 ? 1 : _pagination.page,
    DriverChatConversationsState.refreshing,
  );

  /// Jumps to an explicit page. Out-of-range requests are ignored; the backend
  /// clamps them anyway, but not issuing the call at all is cheaper.
  Future<void> goToPage(int target) async {
    if (target < 1 || isBusy) {
      return;
    }
    if (_pagination.totalPages > 0 && target > _pagination.totalPages) {
      return;
    }
    await _loadPage(target, DriverChatConversationsState.loading);
  }

  Future<void> nextPage() =>
      hasNextPage ? goToPage(_pagination.page + 1) : Future<void>.value();

  Future<void> previousPage() =>
      hasPreviousPage ? goToPage(_pagination.page - 1) : Future<void>.value();

  Future<void> _loadPage(
    int target,
    DriverChatConversationsState busyState,
  ) async {
    final sessionGeneration = stateGeneration;
    try {
      // Supersede any in-flight page request: only the newest one may land.
      _requestToken?.cancel('driver chat conversations superseded');
      final generation = ++_requestGeneration;
      final token = CancelToken();
      _requestToken = token;

      _state = busyState;
      _errorMessage = null;
      notifyListeners();

      try {
        final page = await guardSession(
          _repository.listConversations(
            page: target,
            limit: pageSize,
            cancelToken: token,
          ),
          sessionGeneration,
        );
        if (!_isCurrent(generation)) {
          return;
        }
        // A page replaces the visible list outright. These are pages, not an
        // infinite scroll, so merging older rows in would be wrong.
        _conversations
          ..clear()
          ..addAll(page.conversations);
        _pagination = page.pagination;
        _lastLoadedAt = DateTime.now();
        _state =
            _conversations.isEmpty
                ? DriverChatConversationsState.empty
                : DriverChatConversationsState.loaded;
      } catch (error) {
        if (!acceptsState(sessionGeneration)) throw const SessionChanged();

        if (!_isCurrent(generation) || _isCancelled(error)) {
          return;
        }
        _errorMessage = _safeMessage(error);
        _state = DriverChatConversationsState.error;
      } finally {
        if (acceptsState(sessionGeneration) && _isCurrent(generation)) {
          _requestToken = null;
          notifyListeners();
        }
      }
    } on SessionChanged {
      return;
    }
  }

  /// Refreshes the global badge figure.
  ///
  /// Guarded by a single in-flight flag: the list and the bubble can both ask
  /// at once, and one request is enough.
  Future<void> refreshUnreadCount() async {
    final sessionGeneration = stateGeneration;
    try {
      if (_unreadRequestInFlight) {
        return;
      }
      _unreadRequestInFlight = true;
      final token = CancelToken();
      _unreadToken = token;

      try {
        final count = await guardSession(
          _repository.getUnreadCount(cancelToken: token),
          sessionGeneration,
        );
        if (token.isCancelled) {
          return;
        }
        // Only a changed figure is worth a rebuild. The poller runs every 15
        // seconds and the count is usually the same, so notifying regardless
        // would repaint the badge for nothing.
        final normalized = count < 0 ? 0 : count;
        if (_unreadCount != normalized) {
          _unreadCount = normalized;
          notifyListeners();
        }
      } catch (error) {
        if (!acceptsState(sessionGeneration)) throw const SessionChanged();

        if (!_isCancelled(error)) {
          _errorMessage = _safeMessage(error);
          notifyListeners();
        }
      } finally {
        if (acceptsState(sessionGeneration)) {
          _unreadRequestInFlight = false;
          if (identical(_unreadToken, token)) {
            _unreadToken = null;
          }
        }
      }
    } on SessionChanged {
      return;
    }
  }

  // ---------------------------------------------------------------------------
  // The one app-wide unread poller
  // ---------------------------------------------------------------------------

  /// Starts keeping the badge fresh. Safe to call repeatedly: only one timer
  /// can exist, so however many widgets ask, the app polls once.
  ///
  /// Only `unread_count` is fetched — the badge never costs a conversation page
  /// or a message window.
  void startUnreadPolling({bool immediate = true}) {
    _unreadPollingRequested = true;
    _unreadPollingPaused = false;
    _ensureUnreadTimer();
    if (immediate) {
      unawaited(refreshUnreadCount());
    }
  }

  /// Stops the loop and forgets it was wanted, for logout and session end.
  /// [resumeUnreadPolling] will not restart it.
  void stopUnreadPolling() {
    _unreadPollingRequested = false;
    _unreadPollingPaused = false;
    _cancelUnreadTimer();
  }

  /// Suspends the loop while the app is in the background, without forgetting
  /// that it should run again.
  void pauseUnreadPolling() {
    _unreadPollingPaused = true;
    _cancelUnreadTimer();
  }

  /// Resumes a paused loop. A no-op unless [startUnreadPolling] ran first, so a
  /// stray foreground event cannot start polling for a signed-out driver.
  void resumeUnreadPolling({bool immediate = true}) {
    if (!_unreadPollingRequested) {
      return;
    }
    _unreadPollingPaused = false;
    _ensureUnreadTimer();
    if (immediate) {
      unawaited(refreshUnreadCount());
    }
  }

  void _ensureUnreadTimer() {
    if (!_unreadPollingRequested ||
        _unreadPollingPaused ||
        _unreadTimer != null) {
      return;
    }
    _unreadTimer = Timer.periodic(
      unreadPollingInterval,
      (_) => unawaited(refreshUnreadCount()),
    );
  }

  void _cancelUnreadTimer() {
    _unreadTimer?.cancel();
    _unreadTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Push signals
  // ---------------------------------------------------------------------------

  /// The thread currently on screen, if any, and how to ask it for new
  /// messages. Registered by the conversation page while it is mounted.
  ///
  /// This lives here because this provider is the one app-wide chat object; a
  /// push signal arrives with no route context and needs somewhere to ask
  /// "is that thread open?" without a second state manager.
  int? _openConversationId;
  Future<void> Function()? _openConversationFetchNewer;

  int? get openConversationId => _openConversationId;

  void registerOpenConversation(
    int conversationId,
    Future<void> Function() fetchNewer,
  ) {
    _openConversationId = conversationId;
    _openConversationFetchNewer = fetchNewer;
  }

  void unregisterOpenConversation(int conversationId) {
    // Guarded, so a page disposing after its replacement registered cannot
    // clear the newer registration.
    if (_openConversationId == conversationId) {
      _openConversationId = null;
      _openConversationFetchNewer = null;
    }
  }

  /// Reacts to a `driver_chat_message` push while the app is in the foreground.
  ///
  /// The push is a signal only: nothing from it is written into state. The
  /// badge is re-read from the server, and an open thread refetches through its
  /// own cursor, which is what keeps a signal and a poll arriving together from
  /// showing one message twice.
  Future<void> handleChatSignal(int conversationId) async {
    if (conversationId <= 0) {
      return;
    }
    await refreshUnreadCount();

    final fetchNewer = _openConversationFetchNewer;
    if (fetchNewer != null && _openConversationId == conversationId) {
      await fetchNewer();
    }
  }

  /// Whether this driver may open [conversationId], asked of the server.
  ///
  /// The notification payload proves nothing, so the thread is probed through
  /// the authenticated API: the backend answers CHAT_ACCESS_DENIED for a
  /// conversation that is not this driver's and for one that does not exist,
  /// and both land here as false. A rejected session propagates instead —
  /// DRIVER_INACTIVE must reach the session interceptor, not be swallowed.
  Future<bool> canOpenNotifiedConversation(int conversationId) async {
    final sessionGeneration = stateGeneration;
    try {
      if (conversationId <= 0) {
        return false;
      }
      await guardSession(
        _repository.getMessages(conversationId: conversationId, limit: 1),
        sessionGeneration,
      );
      // The session may have changed while the probe was in flight.
      return acceptsState(sessionGeneration);
    } on SessionChanged {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the thread for a shipment, opening it server-side if needed.
  ///
  /// Returns null when the call failed or the session moved on, so a caller can
  /// only ever navigate to a conversation this driver was actually handed.
  /// [errorMessage] carries the reason on failure.
  ///
  /// The result is merged into the visible page only when that page already
  /// shows this conversation. A thread that is not on the page is left alone:
  /// inserting it would put a row on a page it does not belong to and make the
  /// pager's counts a lie. A newly created one makes the loaded page stale by
  /// one row, which the next [refresh] corrects.
  Future<DriverChatConversation?> resolveShipmentConversation(
    int shipmentId,
  ) async {
    final sessionGeneration = stateGeneration;
    try {
      if (shipmentId <= 0) {
        return null;
      }

      final token = CancelToken();
      _resolveTokens.add(token);
      try {
        final result = await guardSession(
          _repository.getOrCreateShipmentConversation(
            shipmentId: shipmentId,
            cancelToken: token,
          ),
          sessionGeneration,
        );
        if (token.isCancelled) {
          return null;
        }

        _errorMessage = null;
        _mergeResolvedConversation(result.conversation);
        return result.conversation;
      } catch (error) {
        if (!acceptsState(sessionGeneration)) throw const SessionChanged();

        if (!_isCancelled(error)) {
          _errorMessage = _safeMessage(error);
          notifyListeners();
        }
        return null;
      } finally {
        if (acceptsState(sessionGeneration)) {
          _resolveTokens.remove(token);
        }
      }
    } on SessionChanged {
      return null;
    }
  }

  /// Refreshes the visible row for a conversation the server just described.
  void _mergeResolvedConversation(DriverChatConversation conversation) {
    final index = _conversations.indexWhere(
      (existing) => existing.conversationId == conversation.conversationId,
    );
    if (index < 0) {
      return;
    }

    final previous = _conversations[index];
    if (previous.unreadCount != conversation.unreadCount) {
      final updated =
          _unreadCount + (conversation.unreadCount - previous.unreadCount);
      _unreadCount = updated < 0 ? 0 : updated;
    }
    _conversations[index] = conversation;
    notifyListeners();
  }

  /// Applies an authoritative per-conversation unread figure — the one
  /// `mark_read` returns — and moves the global badge by the same delta.
  ///
  /// The server value is used as-is; nothing is guessed. A conversation that is
  /// not on the current page is ignored here, because without its previous
  /// unread figure the delta cannot be computed; [refreshUnreadCount] is the
  /// right call in that case.
  void applyConversationUnread(int conversationId, int unreadCount) {
    final normalized = unreadCount < 0 ? 0 : unreadCount;
    final index = _conversations.indexWhere(
      (conversation) => conversation.conversationId == conversationId,
    );
    if (index < 0) {
      return;
    }

    final current = _conversations[index];
    final difference = normalized - current.unreadCount;
    if (difference == 0) {
      return;
    }
    _conversations[index] = current.copyWith(unreadCount: normalized);
    final updated = _unreadCount + difference;
    _unreadCount = updated < 0 ? 0 : updated;
    notifyListeners();
  }

  /// Sets the global badge from an authoritative value.
  void applyGlobalUnread(int unreadCount) {
    final normalized = unreadCount < 0 ? 0 : unreadCount;
    if (_unreadCount == normalized) {
      return;
    }
    _unreadCount = normalized;
    notifyListeners();
  }

  /// Moves a conversation to the top carrying its newest message, so the list
  /// reflects activity without waiting for a refresh.
  void applyLatestMessage(DriverChatMessage message) {
    final index = _conversations.indexWhere(
      (conversation) => conversation.conversationId == message.conversationId,
    );
    if (index < 0) {
      return;
    }
    final current = _conversations.removeAt(index);
    _conversations.insert(
      0,
      current.copyWith(
        lastMessage: message.message,
        lastMessageType: message.messageType,
        lastMessageSenderRole: message.senderRole,
        lastMessageAt: message.createdAt ?? current.lastMessageAt,
      ),
    );
    notifyListeners();
  }

  /// True only while [generation] is still the newest request. Disposal is
  /// already covered: [acceptsState] is false once the notifier is disposed.
  bool _isCurrent(int generation) => generation == _requestGeneration;

  static bool _isCancelled(Object error) =>
      error is ChatException && error.code == 'REQUEST_CANCELLED';

  static String _safeMessage(Object error) =>
      error is ChatException ? error.safeMessage : 'chat_unknown_error';

  /// Wipes everything the previous driver could see. Called by
  /// [UserSessionState] on logout and on account switch.
  @override
  @protected
  void clearUserState() {
    _requestGeneration++;
    // The badge stops polling the moment the account boundary is crossed, so
    // the next driver never inherits a running timer or a pending answer.
    _unreadPollingRequested = false;
    _unreadPollingPaused = false;
    _cancelUnreadTimer();
    _requestToken?.cancel('driver chat session cleared');
    _unreadToken?.cancel('driver chat session cleared');
    for (final token in _resolveTokens) {
      token.cancel('driver chat session cleared');
    }
    _resolveTokens.clear();
    _requestToken = null;
    _unreadToken = null;
    _unreadRequestInFlight = false;
    _openConversationId = null;
    _openConversationFetchNewer = null;
    _conversations.clear();
    _state = DriverChatConversationsState.initial;
    _pagination = DriverChatPagination.empty;
    _unreadCount = 0;
    _errorMessage = null;
    _lastLoadedAt = null;
  }

  @override
  void dispose() {
    _requestGeneration++;
    _unreadPollingRequested = false;
    _cancelUnreadTimer();
    _requestToken?.cancel('driver chat conversations disposed');
    _unreadToken?.cancel('driver chat conversations disposed');
    for (final token in _resolveTokens) {
      token.cancel('driver chat conversations disposed');
    }
    _resolveTokens.clear();
    _requestToken = null;
    _unreadToken = null;
    super.dispose();
  }
}
